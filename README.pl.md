# DaVinci Resolve Project Server

[English](README.md) · [Polski](README.pl.md)

Uruchom na własnym komputerze lub NAS-ie bibliotekę projektów DaVinci Resolve, z której możesz korzystać na kilku komputerach. Docker uruchamia PostgreSQL, automatyczne kopie i pgAdmin. Jeśli chcesz zarządzać dostępem zespołu w przeglądarce, wybierz wariant z panelem WWW **DaVinci Project Manager**.

| Co chcesz uruchomić | Od czego zacząć |
| --- | --- |
| PostgreSQL, automatyczne kopie i pgAdmin | [Zobacz podstawowy plik Compose](davinci-resolve-project-server.yml) |
| Ten sam zestaw z panelem WWW do zarządzania dostępem | [Zobacz plik Compose z panelem WWW](davinci-resolve-project-server-with-manager.yml) |
| Zestaw do samodzielnego zbudowania i dostosowania | [Zainstaluj z ZIP-a repozytorium](#pierwsze-uruchomienie) |

[Instalacja z jednego pliku](#instalacja-z-jednego-pliku) · [Konta w przeglądarce](#zarządzanie-dostępem-do-bibliotek-w-przeglądarce) · [Panel WWW na Unraidzie](#unraid-community-apps) · [Ustawienia](#dodatkowe-ustawienia) · [Najczęstsze problemy](#najczęstsze-problemy)

## Instalacja z jednego pliku

1. Otwórz wybrany plik Compose z tabeli powyżej. Na GitHubie skopiuj całą treść przyciskiem kopiowania nad kodem.
2. Utwórz nowy stack w edytorze, nadaj mu nazwę i wklej skopiowaną treść.
3. W sekcji zmiennych środowiskowych wpisz ustawienia z tabeli.
4. Wdróż stack. Docker pobierze obrazy i zbuduje panel ze źródeł wskazanych w Compose, jeśli wybierzesz wariant z panelem.

Z terminala zapisz wybrany plik jako `compose.yml`, wpisz ustawienia do pliku `.env` w tym samym katalogu i uruchom `docker compose up -d`.

| Zmienna | Co podać |
| --- | --- |
| `POSTGRES_PASSWORD` | Hasło do bazy, używane z loginem `postgres` w Resolve. |
| `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD` | E-mail i osobne hasło do pgAdmin. |
| `POSTGRES_BIND_IP` | Adres LAN lub VPN hosta Docker, np. `192.168.1.50`. Domyślne `127.0.0.1` oznacza dostęp z tego samego komputera. |
| `RESOLVE_LIBRARY` | Nazwa, którą podasz w Resolve podczas tworzenia biblioteki. Domyślnie `studio`. |
| `PANEL_ADMIN_PASSWORD` | Hasło konta `admin` w panelu WWW. Ustaw osobne hasło o długości co najmniej 8 znaków. |
| `POSTGRES_VERSION` | Opcjonalnie `16`, `17` albo `18`. Domyślnie `18`. |

W DaVinci Resolve wybierz **Network → Add Project Library → Create**, podaj adres hosta i nazwę z `RESOLVE_LIBRARY`. Harmonogram kopii domyślnie korzysta z tej nazwy. Jeśli chcesz kopiować inną bibliotekę lub kilka bibliotek, ustaw `BACKUP_DATABASES`.

PostgreSQL używa portu TCP `5432`. pgAdmin otworzysz w przeglądarce pod adresem z `POSTGRES_BIND_IP`, domyślnie na porcie `3001`.

Dane i kopie domyślnie trafiają do woluminów Dockera. Jeśli chcesz zapisywać kopie w konkretnym katalogu na NAS-ie, ustaw `BACKUP_DIR` na jego pełną ścieżkę. Te pliki Compose są przeznaczone do nowej instalacji. Przy przenoszeniu istniejącej bazy użyj kopii i odtworzenia w nowym stacku.

<a name="opcjonalny-panel-www"></a>

### Zarządzanie dostępem do bibliotek w przeglądarce

Panel WWW DaVinci Project Managera działa na serwerze w Dockerze. W przeglądarce możesz utworzyć konto, zmienić hasło i wybrać, do których bibliotek dana osoba ma dostęp. Projekty otwiera się w DaVinci Resolve. Jeśli chcesz tylko udostępnić bibliotekę, wystarczy podstawowy Compose.

1. Wybierz [Compose z panelem WWW](davinci-resolve-project-server-with-manager.yml) i ustaw `PANEL_ADMIN_PASSWORD`. Panel odczyta ustawienia połączenia z Compose. Python jest już w kontenerze.
2. Utwórz w Resolve bibliotekę o nazwie podanej w `RESOLVE_LIBRARY`. Kontener `panel-setup` zarejestruje ją w panelu.
3. Na komputerze z Dockerem przy ustawieniach domyślnych otwórz [panel lokalny](http://127.0.0.1:3012). Jeśli w `POSTGRES_BIND_IP` podajesz adres NAS-a, użyj go również w przeglądarce, np. `http://192.168.1.50:3012`. Zaloguj się jako `admin` hasłem z `PANEL_ADMIN_PASSWORD`.

Panel uruchamia się po angielsku. Polski możesz wybrać już na ekranie logowania lub później w pasku bocznym.

Jeśli podłączysz aplikację desktopową do tego samego rejestru kont, zobaczysz w niej te same konta i przydziały. Grupy tworzysz w aplikacji desktopowej. Panel WWW pokazuje, z której grupy wynika dostęp, także po odebraniu indywidualnego przydziału. [Instrukcja obsługi grup po angielsku](https://github.com/LukaszOn/davinci-project-manager/blob/main/GUIDE.md#user-groups)

### Połączenie z desktopowym Managerem

W **Połączeniach** wpisz ten sam adres serwera i port `5432` co w Resolve. Podaj login i hasło PostgreSQL. W **Opcjach połączenia** zostaw `postgres` w polu **Baza startowa**. Pliki Compose uruchamiają serwer bez certyfikatu TLS. W zaufanej sieci lokalnej lub prywatnym VPN wybierz dla takiej instalacji **TLS opcjonalny**. Jeśli serwer ma skonfigurowany certyfikat, wybierz **TLS z weryfikacją** i użyj nazwy hosta z certyfikatu.

Po połączeniu wybierz bibliotekę utworzoną w Resolve. [Wydania DaVinci Project Manager](https://github.com/LukaszOn/davinci-project-manager/releases)

## Pierwsze uruchomienie

Otwórz [listę plików repozytorium](https://github.com/LukaszOn/davinci-resolve-project-server), wybierz **Code → Download ZIP** i rozpakuj cały katalog na komputerze z Dockerem. Ten wariant Compose korzysta także z plików w podkatalogach.

| Plik | Do czego służy |
| --- | --- |
| [`docker-compose.yml`](docker-compose.yml) | Podstawowa instalacja z bazą, kopiami i pgAdmin. |
| [`.env.example`](.env.example) | Wzór ustawień. Skopiuj go do `.env` i uzupełnij własne wartości. |
| [`compose.panel.yml`](compose.panel.yml) | Rozszerzenie podstawowej instalacji o panel WWW. |

### 1. Przygotuj ustawienia

Otwórz terminal **na komputerze, na którym działa Docker**, w rozpakowanym katalogu zawierającym `docker-compose.yml`. Do katalogu możesz też przejść poleceniem `cd "ścieżka do rozpakowanego folderu"`. Polecenie `docker compose version` powinno wyświetlić numer wersji. Jeśli go brakuje, skorzystaj z [instrukcji instalacji Docker Compose](https://docs.docker.com/compose/install/).

Przy pierwszej instalacji utwórz plik `.env` na podstawie dołączonego wzoru.

**Linux, macOS lub terminal NAS-a**

```sh
cp .env.example .env
```

**Windows PowerShell**

```powershell
Copy-Item -LiteralPath .env.example -Destination .env
```

Otwórz `.env` w edytorze tekstu. Pliki zaczynające się od kropki bywają ukryte. Na Windows sprawdź, czy plik nazywa się dokładnie `.env`.

| Ustawienie w `.env` | Co wpisać |
| --- | --- |
| `POSTGRES_PASSWORD` | Własne hasło do PostgreSQL. Użyjesz go przy pierwszym połączeniu z Resolve. |
| `PGADMIN_DEFAULT_EMAIL` | Adres e-mail, którym zalogujesz się do pgAdmin. |
| `PGADMIN_DEFAULT_PASSWORD` | Osobne hasło do pgAdmin. |
| `POSTGRES_BIND_IP` | Adres komputera z Dockerem, pod którym Resolve ma się łączyć. Wybierz go z tabeli poniżej. |
| `RESOLVE_LIBRARY` | Podaj nazwę biblioteki z Resolve, np. `editing_projects`. Domyślna to `studio`. Jeśli chcesz kopiować inną bibliotekę lub kilka bibliotek, ustaw `BACKUP_DATABASES`. |

Trzymaj `.env` u siebie, bo zawiera hasła. Wartości zawierające znak `$` możesz zapisać w pojedynczych cudzysłowach. [Składnia `.env` w Docker Compose](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/#env-file-syntax)

| Gdzie działa Resolve? | `POSTGRES_BIND_IP` w `.env` | Adres w Resolve |
| --- | --- | --- |
| Na tym samym komputerze co Docker | `127.0.0.1` | `127.0.0.1` |
| Na innym komputerze w tej samej sieci | Adres LAN komputera z Dockerem, np. `192.168.1.50` | Ten sam adres LAN |
| Na innym komputerze w prywatnym VPN | Adres VPN komputera z Dockerem | Ten sam adres VPN |

`127.0.0.1` oznacza „ten komputer”. Jeśli Docker działa na NAS-ie, a Resolve na laptopie, użyj adresu NAS-a. Znajdziesz go w ustawieniach sieciowych urządzenia lub na liście urządzeń w routerze. Stack używa portu **TCP 5432**. Jeśli zapora blokuje połączenie, dopuść ten port w zaufanej sieci lokalnej lub VPN. [Jak Docker udostępnia porty](https://docs.docker.com/engine/network/port-publishing/)

### 2. Uruchom serwer

W tym samym katalogu wykonaj poniższe polecenia.

```sh
docker compose config --quiet
docker compose up -d --build --wait --wait-timeout 180
docker compose ps -a
```

Pierwsze uruchomienie pobierze obrazy i zbuduje pomocniczy kontener pgAdmin. W wyniku `ps -a` usługi `postgres`, `pgbackups` i `pgadmin` powinny działać. `pgadmin-config` przygotowuje ustawienia i kończy pracę ze statusem `Exited (0)`.

Dane PostgreSQL domyślnie trafiają do `./data`, a kopie do `./backups`. Aby zatrzymać usługi z zachowaniem danych, użyj `docker compose stop`.

### 3. Utwórz bibliotekę w DaVinci Resolve

W **Project Manager** otwórz listę bibliotek, wybierz **Network → Add Project Library → Create** i uzupełnij pola.

| Pole w Resolve | Co wpisać |
| --- | --- |
| **Name** | Dokładną nazwę wpisaną w `RESOLVE_LIBRARY`. |
| **Location** | Adres komputera z Dockerem, np. `127.0.0.1` lub adres NAS-a z kroku 1. |
| **Username** | Login z `POSTGRES_USER` w `.env`, domyślnie `postgres`. |
| **Password** | Hasło z `POSTGRES_PASSWORD` w `.env`. |

Kliknij **Create**, utwórz projekt testowy i zapisz go. Do istniejącej biblioteki użyj zakładki **Connect** i podaj jej dokładną nazwę wraz z danymi konta, które ma do niej dostęp. [Dokumentacja Resolve w serwisie Blackmagic Design](https://www.blackmagicdesign.com/support/family/davinci-resolve-and-fusion)

Instalacja z ZIP-a tworzy też bazę startową `database`. Harmonogram kopii korzysta z `RESOLVE_LIBRARY`. Jeśli w starszej instalacji cel kopii wynikał z `POSTGRES_DB`, przed aktualizacją wpisz tę nazwę w `BACKUP_DATABASES`.

### 4. Sprawdź pierwszą kopię

Przy jednej bibliotece sprawdź, czy `RESOLVE_LIBRARY` odpowiada nazwie w Resolve. Przy kilku podaj listę po przecinku, np. `BACKUP_DATABASES=editing_projects,sound_projects`. Zastosuj ustawienia i wykonaj kopię.

```sh
docker compose up -d pgbackups
docker compose exec -T pgbackups /backup.sh
```

Po komunikacie `SQL backup created successfully` sprawdź, czy w katalogu `backups/last/` jest plik z nazwą biblioteki i rozszerzeniem `.backup`. Domyślnie kopie uruchamiają się codziennie o **02:30 UTC**. Żeby sprawdzić kopię, odtwórz ją na osobnej instancji i otwórz projekt w Resolve. Archiwum zawiera wybraną bibliotekę. Jeśli po awarii chcesz przywrócić też dostęp zespołu, uwzględnij role PostgreSQL, rejestr kont Managera w bazie `postgres` i reguły dostępu do bibliotek. Pliki wideo wymagają osobnej kopii.

## Odtworzenie serwera razem z kontami

Archiwum z harmonogramu pozwala odtworzyć jedną bibliotekę w Managerze. Na własnym serwerze fizyczna kopia całej instancji PostgreSQL zachowuje też hasła ról, grupy i powiązania kont z bibliotekami.

1. Na zaufanym komputerze do kopii użyj narzędzi z tej samej głównej wersji PostgreSQL co serwer. Login do kopii wymaga uprawnienia do replikacji i pasującej reguły dla replikacji w `pg_hba.conf`. Podstaw własny host i login oraz wybierz pusty katalog docelowy. Przykład zakłada, że wszystkie dane są w `PGDATA`.
2. Wykonaj oba polecenia. Zweryfikowaną kopię przechowuj na osobnym nośniku z ograniczonym dostępem.

```sh
pg_basebackup -h db.example.internal -U backup_operator -D studio-cluster -Fp -X stream -P -W
pg_verifybackup studio-cluster
```

3. Do próby odtworzenia **skopiuj** zweryfikowany katalog do nowego, pustego woluminu. Nadaj prawa właściciela systemowemu użytkownikowi PostgreSQL i uruchom tę samą główną wersję PostgreSQL na zgodnej platformie, pod odizolowanym adresem. Zachowaj układ katalogów zgodny z `PGDATA`. Osobno zabezpiecz konfigurację PostgreSQL przechowywaną poza tym katalogiem, ustawienia Compose, sekrety panelu i media.
4. Otwórz projekt na dotychczasowym koncie użytkownika. Zapisz zmianę i sprawdź, czy konto ma dostęp do biblioteki przydzielonej przez grupę oraz czy serwer odmawia dostępu do nieprzydzielonej biblioteki. Na pierwotnym serwerze projekt powinien nadal mieć poprzednią treść.

## Gdzie się zalogować

| Narzędzie | Gdzie je otworzyć | Dane logowania |
| --- | --- | --- |
| DaVinci Resolve | Zakładka **Network**. PostgreSQL używa portu **5432**. | Login i hasło PostgreSQL. |
| pgAdmin | [`http://127.0.0.1:3001`](http://127.0.0.1:3001) na komputerze z Dockerem. | E-mail i hasło `PGADMIN_DEFAULT_*` z głównego `.env`. |
| DaVinci Project Manager WWW | [`http://127.0.0.1:3012`](http://127.0.0.1:3012) po włączeniu opcjonalnego panelu. | Login to `admin`. Przy instalacji z jednego pliku hasło znajdziesz w ustawieniach stacka pod `PANEL_ADMIN_PASSWORD`, a przy instalacji z ZIP-a w `panel/.env`. |

Adresy stron dotyczą przeglądarki uruchomionej na komputerze z Dockerem. Na NAS-ie bez przeglądarki możesz otworzyć pgAdmin z komputera w zaufanej sieci lokalnej. Ustaw `PGADMIN_BIND_IP` na adres LAN NAS-a, uruchom ponownie usługę poleceniem `docker compose up -d pgadmin` i otwórz np. `http://192.168.1.50:3001`, podstawiając swój adres. Przy pierwszym otwarciu połączenia **DaVinci Resolve** w pgAdmin podaj hasło PostgreSQL.

## Dodanie panelu do serwera zainstalowanego z ZIP-a

Wykonaj te kroki tylko wtedy, gdy serwer już działa z pliku `docker-compose.yml` z repozytorium i chcesz dodać do niego panel. W gotowym wariancie Compose z panelem konfigurację wykonuje Docker.

<details>
<summary>Polecenia dla działającej instalacji z ZIP-a</summary>

Zacznij od działającej biblioteki z kroku 3. W terminalu z powłoką `sh`, Pythonem 3 i dostępem do tego samego Dockera przejdź do głównego katalogu repozytorium. Przykład rejestruje istniejącą bibliotekę `editing_projects`. Wstaw jej dokładną nazwę.

```sh
python3 panel/configure.py init --db-host postgres --title 'DaVinci Project Manager' --output panel/.env

PANEL_ENV_FILE=.env \
  PANEL_POSTGRES_CONTAINER="$(docker compose ps -q postgres)" \
  PANEL_POSTGRES_ADMIN="$(docker compose exec -T postgres printenv POSTGRES_USER)" \
  sh panel/install-db.sh editing_projects

docker compose -f docker-compose.yml -f compose.panel.yml up -d --build
```

Pierwsze polecenie tworzy oddzielny `panel/.env` z hasłem do panelu. Zachowaj ten plik przy aktualizacji. Aby dodać kolejną bibliotekę, wykonaj ponownie krok z `install-db.sh`, podając jej nazwę. Instalator używa `psql` z kontenera i ustawia w PostgreSQL reguły dostępu dla kont panelu.

Otwórz adres panelu z tabeli powyżej. Aby ustawić jego adres lub port, zmień `PANEL_BIND_IP` lub `PANEL_PORT` w głównym `.env` i zastosuj zmianę przez polecenie z oboma plikami Compose. Jeśli panel działa za proxy HTTPS, ustaw `PANEL_SECURE_COOKIE=1` w `panel/.env`.

</details>

<details>
<summary>Dla osób testujących lokalne zmiany w kodzie panelu</summary>

W pełnej kopii repozytorium dodaj `PANEL_BUILD_CONTEXT=./panel` i `PANEL_IMAGE=davinci-project-manager-web:local` do ustawień wariantu jednoplikowego z panelem. Następnie uruchom `docker compose -f davinci-resolve-project-server-with-manager.yml up -d --build`. Docker zbuduje obraz z lokalnego kodu.

</details>

## Unraid Community Apps

Szablon Unraid instaluje panel WWW. Panel potrzebuje działającego PostgreSQL z modułem dostępu i co najmniej jedną zarejestrowaną biblioteką Resolve. Jeśli masz już moduł, skorzystaj z jego konfiguracji.

Jeśli PostgreSQL działa w lokalnym kontenerze i konfigurujesz moduł po raz pierwszy, uruchom poniższe polecenie w katalogu repozytorium. Podstaw nazwę kontenera serwera i nazwę biblioteki.

```sh
PANEL_POSTGRES_CONTAINER=your-postgres \
  PANEL_ENV_FILE="$PWD/panel/.env" \
  sh panel/install-db.sh editing_projects
```

Instalator zapisze dane panelu w `panel/.env`. Jeśli administrujesz PostgreSQL z konta o nazwie innej niż `postgres`, do polecenia dodaj `PANEL_POSTGRES_ADMIN` z nazwą tego konta.

Jeśli widzisz **DaVinci Project Manager** w **Apps**, wybierz **Install**. Aby zainstalować go ręcznie, otwórz [szablon XML](templates/davinci-project-manager.xml) na GitHubie. Kliknij **Download raw file**, zapisz plik w `/boot/config/plugins/dockerMan/templates-user/` i wybierz go w **Docker → Add Container**.

W polu **PostgreSQL host** wpisz adres dostępny z kontenera panelu. Domyślne ustawienia to port PostgreSQL `5432`, baza rejestru kont `postgres` i port WebUI `3012`. W polu **PostgreSQL service password** wpisz `PANEL_DB_PASSWORD` z pliku `panel/.env` lub z konfiguracji działającego panelu.

W polu **Panel administrator password** ustaw hasło dla konta `admin` (co najmniej 8 znaków). Otwórz **WebUI** i zaloguj się na to konto. Po restarcie kontenera zaloguj się ponownie tym samym hasłem.

### Dostęp do plików kopii na Unraidzie

W polu **Backup folder** wybierz katalog na Unraidzie. Domyślna ścieżka to `/mnt/user/backups/davinci-resolve`. Unraid mapuje ten katalog w kontenerze panelu jako `/backups` z dostępem tylko do odczytu.

Jeśli kopie wykonuje `pgbackups` ze stacka Compose Project Servera, ustaw katalog kopii przez `BACKUP_DIR` w Compose. W polu **Backup folder** możesz wskazać tę samą ścieżkę.

Pliki `.backup` znajdziesz w podkatalogu `last/` wybranego katalogu. Jeśli udział `backups` jest dostępny przez SMB, w Windows otwórz np. `\\UNRAID\backups\davinci-resolve\last`. Do odtworzenia skopiuj archiwum z datą w nazwie.

Na docelowym serwerze PostgreSQL zaloguj się jako administrator i utwórz pustą bazę pod wybraną nazwą. Jeśli korzystasz z pgAdmin w przeglądarce, wgraj plik do **My Storage** przez **Tools → Storage Manager**. Kliknij prawym przyciskiem nową bazę, wybierz **Restore**, ustaw format **Custom or tar** i wskaż plik `.backup`. W **Query Options** pozostaw wyłączone **Include CREATE DATABASE statement**, żeby odtworzyć dane w wybranej bazie. [Odtwarzanie w pgAdmin](https://www.pgadmin.org/docs/pgadmin4/latest/restore_dialog.html)

Jeśli na serwerze docelowym brakuje ról z serwera źródłowego, w **Data Options → Do not save** włącz **Owner** i **Privileges**, żeby pominąć ustawienia właścicieli i uprawnień. Aby zarządzać dostępem do odtworzonej biblioteki z panelu, zarejestruj ją na docelowym serwerze.

Przy nowej instalacji PostgreSQL możesz też ustawić katalog danych w tym samym stacku, np. `POSTGRES_DATA_DIR=/mnt/user/appdata/davinci-resolve/postgres`.

## Dodatkowe ustawienia

| Zmienna | Domyślna wartość i zastosowanie |
| --- | --- |
| `POSTGRES_VERSION` | `18`. Możesz ustawić np. `16` lub `17`. Kontener kopii używa tej samej wersji. |
| `POSTGRES_USER`, `POSTGRES_DB` | `postgres` i `database`. Ustawienia pierwszej inicjalizacji bazy. |
| `POSTGRES_DATA_DIR` | `./data/postgres-<wersja>`. Katalog na hoście. W środku PostgreSQL zapisuje dane w `<wersja>/docker`. |
| `BACKUP_DIR`, `BACKUP_DATABASES` | Katalog kopii (domyślnie `./backups` w instalacji z ZIP-a) i opcjonalna lista baz. Przy pustej liście kopiowana jest biblioteka z `RESOLVE_LIBRARY`. |
| `TZ`, `BACKUP_SCHEDULE` | `UTC` i `30 2 * * *`. Dla czasu polskiego ustaw `TZ=Europe/Warsaw`. |
| `BACKUP_KEEP_DAYS`, `BACKUP_KEEP_WEEKS`, `BACKUP_KEEP_MONTHS` | Okresy przechowywania kopii. Domyślnie 7 dni, 4 tygodnie i 6 miesięcy. |
| `PGADMIN_BIND_IP`, `PGADMIN_PORT` | `127.0.0.1` i `3001`. Adres i port pgAdmin na hoście. |

**Wersja PostgreSQL i migracja.** Domyślnie zalecamy PostgreSQL 18 dla nowych instalacji, jeśli działa z Twoją wersją Resolve. Testy automatyczne obejmują stack na PostgreSQL 16, 17 i 18. Zgodność klienta sprawdzisz, tworząc, otwierając i zapisując projekt w osobnej bibliotece testowej. Przy zmianie głównej wersji zachowaj dotychczasowe dane i odtwórz kopię na nowej instancji. Katalog z plikiem `PG_VERSION` bezpośrednio w jego głównym folderze używa innego układu. Do migracji z takiej instalacji wybierz nowy katalog danych. [Testy stacka](https://github.com/LukaszOn/davinci-resolve-project-server/actions/workflows/stack-healthcheck.yml) · [Dokumentacja obrazu PostgreSQL](https://hub.docker.com/_/postgres)

## Najczęstsze problemy

| Co widzisz | Co sprawdzić |
| --- | --- |
| `no configuration file provided` | Uruchom polecenie w katalogu zawierającym `docker-compose.yml`. Sprawdź, czy został rozpakowany cały ZIP. |
| Compose prosi o wartość zmiennej | Sprawdź nazwę `.env` i trzy wymagane pola z kroku 1. |
| Resolve na drugim komputerze nie łączy się | Sprawdź, czy używasz adresu hosta Docker, który podałeś w `POSTGRES_BIND_IP`, i czy port 5432 jest dostępny w tej sieci. |
| Port 5432 jest już zajęty | Sprawdź, czy działa inny PostgreSQL. Dwie instancje na jednym hoście potrzebują osobnych adresów IP, nazw projektu Compose i katalogów danych. |
| Kopie zawierają bazę `database` | Ustaw `BACKUP_DATABASES` na nazwę biblioteki utworzonej w Resolve i powtórz krok 4. |
| Kopia kończy się błędem `ln: … Operation not supported` | Ustaw `BACKUP_DIR` na katalog na lokalnym dysku. Rotacja używa twardych i symbolicznych dowiązań. [Jak działa rotacja kopii](https://github.com/prodrigestivill/docker-postgres-backup-local#how-the-backups-folder-works) |
| Zmieniłem hasło w `.env`, a baza przyjmuje poprzednie | Hasło w `.env` służy do pierwszej inicjalizacji PostgreSQL. Na działającej bazie zmień je najpierw dla odpowiedniej roli PostgreSQL, a potem uaktualnij `.env`. |

Stan usług sprawdzisz poleceniem `docker compose ps -a`, a komunikaty bazy i kopii przez `docker compose logs --tail 50 postgres pgbackups`.

## Projekt źródłowy

Fork [Docker-Davinci-Resolve-Project-Server autorstwa Elliota Matsona](https://github.com/elliotmatson/Docker-Davinci-Resolve-Project-Server). Kod jest udostępniony na licencji [MIT](LICENSE). Projekt jest niezależny od Blackmagic Design.
