# DaVinci Resolve Project Server

[English](README.md) · [Polski](README.pl.md)

Uruchom na własnym komputerze lub NAS-ie bibliotekę projektów DaVinci Resolve, z której może korzystać kilka stacji montażowych. Docker uruchamia PostgreSQL, automatyczne kopie i pgAdmin. Panel WWW **DaVinci Project Manager** do zarządzania kontami i dostępem można dołączyć później.

[Instalacja z jednego pliku](#instalacja-z-jednego-pliku) · [Instalacja z pobranego katalogu](#pierwsze-uruchomienie) · [Ustawienia](#dodatkowe-ustawienia) · [Najczęstsze problemy](#najczęstsze-problemy)

## Instalacja z jednego pliku

Wybierz jeden kompletny plik Compose dla nowej instalacji.

| Wariant | Plik Compose |
| --- | --- |
| PostgreSQL, kopie i pgAdmin | [Podstawowy Compose](https://github.com/LukaszOn/davinci-resolve-project-server/releases/latest/download/davinci-resolve-project-server.yml) |
| PostgreSQL, kopie, pgAdmin i panel WWW | [Compose z panelem](https://github.com/LukaszOn/davinci-resolve-project-server/releases/latest/download/davinci-resolve-project-server-with-manager.yml) |

1. W edytorze stacków utwórz nowy stack, nadaj mu nazwę i wklej zawartość wybranego pliku.
2. W sekcji zmiennych środowiskowych wpisz ustawienia z tabeli.
3. Wdróż stack. Docker pobierze obrazy i zbuduje opcjonalny panel ze źródeł na GitHubie.

Z terminala zapisz wybrany plik jako `compose.yml`, wpisz ustawienia do pliku `.env` w tym samym katalogu i uruchom `docker compose up -d`.

| Zmienna | Co podać |
| --- | --- |
| `POSTGRES_PASSWORD` | Hasło do bazy, używane z loginem `postgres` w Resolve. |
| `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD` | E-mail i osobne hasło do pgAdmin. |
| `POSTGRES_BIND_IP` | Adres LAN lub VPN hosta Docker, np. `192.168.1.50`. Domyślne `127.0.0.1` oznacza dostęp z tego samego komputera. |
| `RESOLVE_LIBRARY` | Nazwa, którą podasz w Resolve podczas tworzenia biblioteki. Domyślnie `studio`. |
| `PANEL_ADMIN_PASSWORD` | Tylko w wariancie z panelem. Osobne hasło o długości co najmniej 32 znaków. |
| `POSTGRES_VERSION` | Opcjonalnie `16`, `17` albo `18`. Domyślnie `18`. |

W DaVinci Resolve wybierz **Network → Add Project Library → Create**, podaj adres hosta i nazwę z `RESOLVE_LIBRARY`. Serwer używa portu `5432`. pgAdmin otworzysz pod adresem hosta z portem `3001`.

Jeśli wybrałeś wariant z panelem, otwórz adres hosta z portem `3012`. Zostaw pole loginu puste i podaj `PANEL_ADMIN_PASSWORD`. Gdy biblioteka pojawi się w PostgreSQL, osobna usługa `panel-setup` zarejestruje ją automatycznie i zakończy pracę. Panel dostaje adres bazy z Compose i łączy się przez własne konto techniczne. Kopie używają tej samej nazwy biblioteki, chyba że ustawisz osobno `BACKUP_DATABASES`.

Dane i kopie domyślnie trafiają do woluminów Dockera. Jeśli chcesz zapisywać kopie w konkretnym katalogu na NAS-ie, ustaw `BACKUP_DIR` na jego pełną ścieżkę. Te pliki Compose są przeznaczone do nowej instalacji. Przy przenoszeniu istniejącej bazy użyj kopii i odtworzenia w nowym stacku.

### Instalacja z pobranego katalogu

| Plik | Do czego służy |
| --- | --- |
| [`docker-compose.yml`](docker-compose.yml) | Podstawowa instalacja z bazą, kopiami i pgAdmin. |
| [`.env.example`](.env.example) | Wzór ustawień. Skopiuj go do `.env` i uzupełnij własne wartości. |
| [`compose.panel.yml`](compose.panel.yml) | Rozszerzenie podstawowej instalacji o panel WWW. |

[**Pobierz ZIP całego repozytorium**](https://github.com/LukaszOn/davinci-resolve-project-server/archive/refs/heads/main.zip) lub wybierz **Code → Download ZIP** nad listą plików na GitHubie. Rozpakuj cały katalog na komputerze z Dockerem. Compose korzysta także z plików w podkatalogach.

[Pierwsze uruchomienie](#pierwsze-uruchomienie) · [Ręczne dołączenie panelu WWW](#opcjonalny-panel-www)

## Pierwsze uruchomienie

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
| **Name** | Nazwę nowej biblioteki, np. `studio_test`. |
| **Location** | Adres komputera z Dockerem, np. `127.0.0.1` lub adres NAS-a z kroku 1. |
| **Username** | Login z `POSTGRES_USER` w `.env`, domyślnie `postgres`. |
| **Password** | Hasło z `POSTGRES_PASSWORD` w `.env`. |

Kliknij **Create**, utwórz projekt testowy i zapisz go. Do istniejącej biblioteki użyj zakładki **Connect** i podaj jej dokładną nazwę wraz z danymi konta, które ma do niej dostęp. [Instrukcja Blackmagic Design](https://documents.blackmagicdesign.com/UserManuals/DaVinciResolveReferenceManual.pdf)

Zwykła baza `database` powstaje przy starcie PostgreSQL. Bibliotekę projektów tworzy Resolve w tym kroku.

### 4. Sprawdź pierwszą kopię

Dopiero po utworzeniu biblioteki wpisz jej nazwę w `BACKUP_DATABASES` w pliku `.env`, np. `BACKUP_DATABASES=studio_test`. Przy kilku bibliotekach rozdziel ich nazwy przecinkami. Zastosuj ustawienia i uruchom kopię ręcznie.

```sh
docker compose up -d pgbackups
docker compose exec -T pgbackups /backup.sh
```

Po komunikacie `SQL backup created successfully` sprawdź, czy w katalogu `backups/last/` jest plik z nazwą biblioteki i rozszerzeniem `.backup`. Domyślnie kopie uruchamiają się codziennie o **02:30 UTC**. Obejmują dane bibliotek. Pliki wideo i role PostgreSQL wymagają osobnych kopii.

## Gdzie się zalogować

| Narzędzie | Gdzie je otworzyć | Dane logowania |
| --- | --- | --- |
| DaVinci Resolve | Zakładka **Network**. PostgreSQL używa portu **5432**. | Login i hasło PostgreSQL. |
| pgAdmin | [`http://127.0.0.1:3001`](http://127.0.0.1:3001) na komputerze z Dockerem. | E-mail i hasło `PGADMIN_DEFAULT_*` z głównego `.env`. |
| DaVinci Project Manager WWW | [`http://127.0.0.1:3012`](http://127.0.0.1:3012) po włączeniu opcjonalnego panelu. | Przy pierwszym logowaniu użyj `PANEL_ADMIN_PASSWORD` z `panel/.env` i zostaw login pusty. |

Adresy stron dotyczą przeglądarki uruchomionej na komputerze z Dockerem. Na NAS-ie bez przeglądarki możesz otworzyć pgAdmin z komputera w zaufanej sieci lokalnej. Ustaw `PGADMIN_BIND_IP` na adres LAN NAS-a, uruchom ponownie usługę poleceniem `docker compose up -d pgadmin` i otwórz np. `http://192.168.1.50:3001`, podstawiając swój adres. Przy pierwszym otwarciu połączenia **DaVinci Resolve** w pgAdmin podaj hasło PostgreSQL.

## Opcjonalny panel WWW

Panel dodaje w przeglądarce zarządzanie kontami i dostępem do bibliotek. Domyślnie używa angielskiego. Aby zmienić język, wybierz **Polski** na ekranie logowania lub na pasku bocznym. Może działać obok [DaVinci Project Manager na desktop](https://github.com/LukaszOn/davinci-project-manager) na tej samej instancji PostgreSQL i bazie rejestru.

<details>
<summary>Jak włączyć panel</summary>

Zacznij od działającej biblioteki z kroku 3. W terminalu z powłoką `sh`, Pythonem 3 i dostępem do tego samego Dockera przejdź do głównego katalogu repozytorium. Przykład rejestruje istniejącą bibliotekę `studio_test`. Wstaw jej dokładną nazwę.

```sh
python3 panel/configure.py init --db-host postgres --title 'DaVinci Project Manager' --output panel/.env

PANEL_ENV_FILE=.env \
  PANEL_POSTGRES_CONTAINER="$(docker compose ps -q postgres)" \
  PANEL_POSTGRES_ADMIN="$(docker compose exec -T postgres printenv POSTGRES_USER)" \
  sh panel/install-db.sh studio_test

docker compose -f docker-compose.yml -f compose.panel.yml up -d --build
```

Pierwsze polecenie tworzy oddzielny `panel/.env` z hasłem do panelu. Zachowaj ten plik przy aktualizacji. Aby dodać kolejną bibliotekę, wykonaj ponownie krok z `install-db.sh`, podając jej nazwę. Instalator używa `psql` z kontenera i ustawia w PostgreSQL reguły dostępu dla kont panelu.

Otwórz adres panelu z tabeli powyżej. Aby ustawić jego adres lub port, zmień `PANEL_BIND_IP` lub `PANEL_PORT` w głównym `.env` i zastosuj zmianę przez polecenie z oboma plikami Compose. Jeśli panel działa za proxy HTTPS, ustaw `PANEL_SECURE_COOKIE=1` w `panel/.env`.

</details>

## Dodatkowe ustawienia

| Zmienna | Domyślna wartość i zastosowanie |
| --- | --- |
| `POSTGRES_VERSION` | `18`. Możesz ustawić np. `16` lub `17`. Kontener kopii używa tej samej wersji. |
| `POSTGRES_USER`, `POSTGRES_DB` | `postgres` i `database`. Ustawienia pierwszej inicjalizacji bazy. |
| `POSTGRES_DATA_DIR` | `./data/postgres-<wersja>`. Katalog na hoście. W środku PostgreSQL zapisuje dane w `<wersja>/docker`. |
| `BACKUP_DIR`, `BACKUP_DATABASES` | `./backups` i lista bibliotek do kopiowania. Bez listy kopiowana jest baza z `POSTGRES_DB`. |
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

Fork [Docker-Davinci-Resolve-Project-Server autorstwa Elliota Matsona](https://github.com/elliotmatson/Docker-Davinci-Resolve-Project-Server). Kod jest udostępniony na licencji [MIT](LICENSE.md). Projekt jest niezależny od Blackmagic Design.
