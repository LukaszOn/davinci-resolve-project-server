import hmac
import os
import re
import secrets
import time
from pathlib import Path
from collections import deque
from datetime import timedelta
from threading import Lock

import psycopg
from flask import Flask, Response, abort, flash, redirect, render_template, request, session, url_for
from psycopg import errors
from psycopg.rows import dict_row
from werkzeug.security import check_password_hash, generate_password_hash

from translations import LEGACY_SQL_MESSAGES, POLISH


def secret_setting(name):
    value = os.environ.get(name, '')
    path = os.environ.get(name + '_FILE', '')
    if value and path:
        raise RuntimeError(f'Set either {name} or {name}_FILE.')
    if path:
        try:
            value = Path(path).read_text(encoding='utf-8').rstrip('\r\n')
        except (OSError, UnicodeError) as error:
            raise RuntimeError(f'Could not read the {name}_FILE secret.') from error
    if len(value) < 32:
        raise RuntimeError(f'{name} must be at least 32 characters long.')
    return value


app = Flask(__name__)
app.config.update(
    SECRET_KEY=secret_setting('PANEL_SESSION_KEY'),
    SESSION_COOKIE_NAME='resolve_panel_session',
    SESSION_COOKIE_SECURE=os.environ.get('PANEL_SECURE_COOKIE') == '1',
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE='Strict',
    SESSION_REFRESH_EACH_REQUEST=False,
    PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
    MAX_CONTENT_LENGTH=144 * 1024,
)
ADMIN_PASSWORD = secret_setting('PANEL_ADMIN_PASSWORD').encode()
DB_PASSWORD = secret_setting('PANEL_DB_PASSWORD')
PANEL_DISPLAY_NAME = os.environ.get('PANEL_DISPLAY_NAME', '').strip() or 'DaVinci Project Manager'
PANEL_MANAGED_LIBRARY = os.environ.get('PANEL_MANAGED_LIBRARY', '')
if len(PANEL_DISPLAY_NAME) > 80:
    raise RuntimeError('PANEL_DISPLAY_NAME can be up to 80 characters long.')
DB_SSLMODE = os.environ.get('PANEL_DB_SSLMODE', 'prefer')
if DB_SSLMODE not in {'disable', 'prefer', 'require', 'verify-ca', 'verify-full'}:
    raise RuntimeError('Invalid PANEL_DB_SSLMODE.')
DB_ROOT_CERT = os.environ.get('PANEL_DB_SSLROOTCERT', '')
LOGIN_NAME = re.compile(r'[a-z][a-z0-9_]{1,30}\Z')
ROLES = {'collaborator': 'Collaborator', 'administrator': 'Administrator'}
LANGUAGE_COOKIE = 'dpm_language'
LANGUAGES = {'en', 'pl'}
MAX_AVATAR = 128 * 1024
LOGIN_DUMMY_HASH = generate_password_hash(secrets.token_urlsafe(32))
FAILED_LOGINS = deque(maxlen=8)
LOGIN_LOCK = Lock()


def database():
    return psycopg.connect(
        host=os.environ.get('PANEL_DB_HOST', 'postgres'),
        port=os.environ.get('PANEL_DB_PORT', '5432'),
        dbname=os.environ.get('PANEL_DB_NAME', 'postgres'),
        user=os.environ.get('PANEL_DB_USER', 'resolve_panel_agent'),
        password=DB_PASSWORD, sslmode=DB_SSLMODE,
        **({'sslrootcert': DB_ROOT_CERT} if DB_ROOT_CERT else {}),
        row_factory=dict_row, connect_timeout=3, application_name='davinci_project_manager_web',
        options='-c statement_timeout=6000 -c lock_timeout=2500',
    )


def panel_administrator(username):
    with database() as conn:
        return conn.execute('SELECT * FROM resolve_access.panel_administrator(%s)', (username,)).fetchone()


@app.before_request
def protect_routes():
    if request.endpoint in ('static', 'healthz'):
        return None
    if request.method == 'POST':
        expected = session.get('csrf', '')
        supplied = request.form.get('csrf', '')
        if not expected or not hmac.compare_digest(expected.encode(), supplied.encode()):
            abort(400)
    if request.endpoint == 'set_language':
        return None
    if request.endpoint != 'login' and not session.get('admin'):
        return redirect(url_for('login'))
    if request.endpoint not in ('login', 'logout') and session.get('principal'):
        try:
            member = panel_administrator(session['principal'])
        except psycopg.Error:
            return render_template('unavailable.html'), 503
        if member is None or [member['login_oid'], member['auth_version']] != session.get('identity'):
            session.clear()
            return redirect(url_for('login'))
    return None


@app.after_request
def protect_response(response):
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; "
        "base-uri 'none'; form-action 'self'; frame-ancestors 'none'"
    )
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['Referrer-Policy'] = 'no-referrer'
    return response


def current_language():
    language = request.cookies.get(LANGUAGE_COOKIE, 'en')
    return language if language in LANGUAGES else 'en'


def translate(message, **values):
    if current_language() == 'pl':
        message = POLISH.get(message, message)
    return message.format(**values) if values else message


@app.post('/language')
def set_language():
    language = request.form.get('language')
    if language not in LANGUAGES:
        abort(400)
    target = url_for('login')
    if session.get('admin'):
        target = url_for('index', biblioteka=request.form.get('library', '')[:63] or None,
                         q=request.form.get('q', '')[:80] or None, osoba=request.form.get('person', '')[:31] or None)
    response = redirect(target, code=303)
    response.set_cookie(LANGUAGE_COOKIE, language, max_age=365 * 24 * 60 * 60,
                        secure=app.config['SESSION_COOKIE_SECURE'], httponly=True, samesite='Strict')
    return response


@app.context_processor
def form_context():
    return {
        'csrf': session.setdefault('csrf', secrets.token_urlsafe(32)),
        'roles': {key: translate(label) for key, label in ROLES.items()},
        'language': current_language(),
        'tr': translate,
        'panel_display_name': PANEL_DISPLAY_NAME,
        'panel_managed_library': PANEL_MANAGED_LIBRARY,
    }


@app.route('/login', methods=['GET', 'POST'])
def login():
    if session.get('admin'):
        return redirect(url_for('index'))
    if request.method == 'POST':
        with LOGIN_LOCK:
            now = time.monotonic()
            while FAILED_LOGINS and FAILED_LOGINS[0] <= now - 60:
                FAILED_LOGINS.popleft()
            if len(FAILED_LOGINS) >= FAILED_LOGINS.maxlen:
                return render_template('login.html', error='Wait one minute before trying again.'), 429
            username = request.form.get('username', '').strip().lower()
            password = request.form.get('password', '')
            member = None
            if LOGIN_NAME.fullmatch(username) and len(password) <= 128:
                try:
                    member = panel_administrator(username)
                except psycopg.Error:
                    return render_template('unavailable.html'), 503
                web_hash = member['panel_hash'] if member else LOGIN_DUMMY_HASH
                authenticated = check_password_hash(web_hash, password) and member is not None
            else:
                authenticated = not username and hmac.compare_digest(ADMIN_PASSWORD, password.encode())
            if authenticated:
                FAILED_LOGINS.clear()
                session.clear()
                session.permanent = True
                session.update(admin=True, csrf=secrets.token_urlsafe(32))
                if member:
                    session.update(principal=username, identity=[member['login_oid'], member['auth_version']])
                return redirect(url_for('index'))
            FAILED_LOGINS.append(now)
        return render_template('login.html', error='Check your administrator username and password.'), 401
    return render_template('login.html')


@app.post('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


def read_directory():
    with database() as conn:
        libraries = [row['name'] for row in conn.execute('SELECT name FROM resolve_access.available_libraries ORDER BY name')]
        groups_available = conn.execute("""
            SELECT to_regclass('resolve_access.member_direct_access') IS NOT NULL AS available
        """).fetchone()['available']
        if groups_available:
            people = conn.execute("""
                SELECT d.*, a.libraries AS direct_libraries,
                       (SELECT jsonb_object_agg(grants.library, grants.groups)
                        FROM (
                            SELECT library, array_agg(g.label ORDER BY lower(g.label), g.group_key) AS groups
                            FROM resolve_access.group_directory g CROSS JOIN LATERAL unnest(g.libraries) library
                            WHERE d.username::text = ANY(g.logins) GROUP BY library
                        ) grants) AS groups_by_library
                FROM resolve_access.directory d JOIN resolve_access.member_direct_access a USING (username)
                ORDER BY lower(d.label), d.username
            """).fetchall()
        else:
            people = conn.execute('SELECT * FROM resolve_access.directory ORDER BY lower(label), username').fetchall()
    return libraries, people


@app.get('/healthz')
def healthz():
    try:
        with database() as conn:
            conn.execute('SELECT name FROM resolve_access.available_libraries LIMIT 1').fetchone()
    except psycopg.Error:
        return 'unavailable\n', 503
    return 'ok\n'


@app.get('/')
def index():
    query = request.args.get('q', '').strip()[:80]
    library_filter = request.args.get('biblioteka', '')
    try:
        libraries, everyone = read_directory()
    except psycopg.Error as error:
        app.logger.warning('Could not read the account directory. SQLSTATE=%s', error.sqlstate)
        return render_template('unavailable.html'), 503
    library_filter = library_filter if library_filter in libraries else ''
    people = [
        person for person in everyone
        if (not library_filter or library_filter in person['libraries'])
        and (not query or query.casefold() in f"{person['label']} {person['username']}".casefold())
    ]
    selected = next((p for p in everyone if p['username'] == request.args.get('osoba')), None)
    if selected is None and people:
        selected = people[0]
    counts = {library: sum(library in person['libraries'] for person in everyone) for library in libraries}
    return render_template(
        'index.html', libraries=libraries, people=people, selected=selected, counts=counts,
        query=query, library_filter=library_filter, total=len(everyone),
        active=sum(person['enabled'] for person in everyone),
    )


def apply(conn, action, username, label=None, verifier=None, library=None):
    conn.execute('SELECT resolve_access.apply_change(%s, %s, %s, %s, %s)', (action, username, label, verifier, library))


def avatar_type(content):
    if content.startswith(b'\x89PNG\r\n\x1a\n') and content.endswith(b'IEND\xaeB`\x82'):
        return 'image/png'
    if content.startswith(b'\xff\xd8\xff') and content.endswith(b'\xff\xd9'):
        return 'image/jpeg'
    return None


@app.get('/people/<username>/avatar')
def member_avatar(username):
    if not LOGIN_NAME.fullmatch(username):
        abort(404)
    with database() as conn:
        avatar = conn.execute('SELECT resolve_access.member_avatar(%s) AS photo', (username,)).fetchone()['photo']
    mimetype = avatar_type(avatar) if avatar else None
    if not mimetype:
        abort(404)
    return Response(avatar, mimetype=mimetype)


@app.post('/people')
def change_person():
    action = request.form.get('action', '')
    username = request.form.get('username', '').strip().lower()
    if not LOGIN_NAME.fullmatch(username):
        flash('Use a username of 2–31 characters. Start with a letter and use a–z, digits, or underscores.', 'error')
        return redirect(url_for('index'), code=303)
    return_url = url_for('index', osoba=username)
    messages = {
        'grant': 'Access granted.', 'revoke': 'Access revoked.',
        'enable': 'Account unlocked.', 'disable': 'Account locked.',
        'edit': 'Account changes saved.', 'password': 'Password updated.',
        'create': 'The account is ready.', 'delete': 'Account deleted.',
    }
    if action not in messages:
        abort(400)
    library = request.form.get('library')
    label = request.form.get('label', '').strip()
    new_login = request.form.get('new_username', username).strip().lower()
    role = request.form.get('account_role', 'collaborator')
    if session.get('principal') == username and (action in ('delete', 'disable') or (action == 'edit' and role != 'administrator')):
        flash('Ask another administrator to change your role or lock your account.', 'error')
        return redirect(return_url, code=303)

    generated = False
    password = None
    if action in ('create', 'password'):
        password = request.form.get('password', '')
        confirmation = request.form.get('password_confirmation', '')
        if password or confirmation:
            if password != confirmation or not 8 <= len(password) <= 128 or '\x00' in password:
                flash('Enter the same password of 8–128 characters twice.', 'error')
                return redirect(return_url, code=303)
        else:
            generated = True
            password = secrets.token_urlsafe(21)

    file = request.files.get('avatar') if action in ('create', 'edit') else None
    photo = file.read(MAX_AVATAR + 1) if file and file.filename else None
    if photo is not None and (len(photo) > MAX_AVATAR or not avatar_type(photo)):
        flash('Select a PNG or JPEG image up to 128 KB.', 'error')
        return redirect(return_url, code=303)

    web_hash = generate_password_hash(password) if password is not None else None
    try:
        with database() as conn:
            verifier = conn.pgconn.encrypt_password(password.encode(), username.encode(), b'scram-sha-256').decode() if password else None
            if action in ('create', 'edit', 'password', 'delete'):
                conn.execute('SELECT resolve_access.change_member(%s,%s,%s,%s,%s,%s,%s,%s,%s)', (
                    action, username, new_login if action == 'edit' else username, label, role, verifier,
                    web_hash, photo, request.form.get('clear_photo') == '1' and photo is None,
                ))
            else:
                apply(conn, action, username, library=library)
            if action == 'revoke' and conn.execute("""
                SELECT EXISTS (
                    SELECT FROM resolve_access.directory WHERE username = %s AND %s = ANY(libraries)
                ) AS still_assigned
            """, (username, library)).fetchone()['still_assigned']:
                messages['revoke'] = 'Direct access revoked. Group access is still active.'
            if action == 'create':
                for library in dict.fromkeys(request.form.getlist('libraries')):
                    apply(conn, 'grant', username, library=library)
    except errors.RaiseException as error:
        message = error.diag.message_primary
        flash(LEGACY_SQL_MESSAGES.get(message, message), 'error')
        return redirect(return_url, code=303)
    except psycopg.Error as error:
        app.logger.warning('Could not save operation %s. SQLSTATE=%s', action, error.sqlstate)
        flash('Could not confirm the change. Refresh the page and check the current state.', 'error')
        return redirect(return_url, code=303)

    if action in ('revoke', 'disable'):
        try:
            with database() as conn:
                conn.execute('SELECT resolve_access.close_revoked_sessions(%s)', (username,))
        except psycopg.Error as error:
            app.logger.warning('Could not close sessions. SQLSTATE=%s', error.sqlstate)
            flash('Access changed. Repeat the operation if you still need to close open connections.', 'error')
            return redirect(return_url, code=303)
    if action == 'delete':
        return_url = url_for('index')
    elif action == 'edit':
        return_url = url_for('index', osoba=new_login)
    if generated:
        return render_template('receipt.html', username=username, password=password, created=action == 'create', return_url=return_url)
    flash(messages[action], 'success')
    return redirect(return_url, code=303)


@app.errorhandler(400)
def invalid_request(_error):
    return render_template('unavailable.html', invalid=True), 400
