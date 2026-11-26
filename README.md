# DaVinci Resolve Project Server

Stack Docker do uruchomienia sieciowych bibliotek projektów DaVinci Resolve. W podstawowym wariancie dostajesz PostgreSQL, automatyczne kopie i pgAdmin. Do tego możesz dołączyć panel WWW **DaVinci Project Manager** do zarządzania kontami i dostępem do bibliotek.

## Wybór PostgreSQL

**PostgreSQL 18 jest domyślną i zalecaną wersją dla nowej instalacji tego projektu**, jeśli działa z Twoją wersją Resolve. Zgodność zależy od wersji klienta Resolve. Przed przeniesieniem działającej biblioteki sprawdź, czy możesz utworzyć, otworzyć i zapisać projekt w bibliotece testowej przy użyciu tej samej wersji Resolve co reszta zespołu.

Ustaw `POSTGRES_VERSION` w `.env`, np. `18`, `17` albo `16`. Compose użyje tego numeru również dla narzędzi do kopii. Przy domyślnych ścieżkach zmiana numeru wskazuje inny katalog danych. Przy przejściu z istniejącego serwera zachowaj stary katalog i przenieś bibliotekę za pomocą kopii oraz odtworzenia. [Dokumentacja obrazu PostgreSQL](https://hub.docker.com/_/postgres)

## Konfiguracja

Skopiuj `.env.example` do `.env`. W tym pliku ustaw hasła oraz adres e-mail do pgAdmin. Zachowaj `.env` u siebie.

| Pole | Co ustawić |
| --- | --- |
| `POSTGRES_VERSION` | Główna wersja PostgreSQL, domyślnie `18`. |
| `POSTGRES_PASSWORD` | Własne hasło do PostgreSQL. Login startowy to `postgres`, chyba że zmienisz `POSTGRES_USER`. |
| `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD` | Adres e-mail i osobne hasło do pgAdmin. |
| `POSTGRES_BIND_IP` | Domyślnie `127.0.0.1`. Dla Resolve na innym komputerze wpisz adres LAN lub VPN hosta Docker. |
| `POSTGRES_DATA_DIR`, `BACKUP_DIR` | Opcjonalne ścieżki na hoście. Sprawdź je, jeśli uruchamiasz stack na Unraidzie, NAS-ie lub innym dysku. |
| `POSTGRES_DB` | Baza tworzona przez PostgreSQL przy pierwszym uruchomieniu, domyślnie `database`. |
| `BACKUP_DATABASES` | Nazwy istniejących bibliotek do kopii, oddzielone przecinkami. Pusta wartość wybiera bazę z `POSTGRES_DB`. |
| `TZ`, `BACKUP_SCHEDULE`, `BACKUP_KEEP_*` | Strefa, harmonogram i retencja. Domyślnie 02:30 UTC oraz 7 kopii dziennych, 4 tygodniowe i 6 miesięcznych. |
| `PGADMIN_BIND_IP`, `PGADMIN_PORT` | Adres i port interfejsu pgAdmin. Domyślnie `127.0.0.1:3001`. |

`POSTGRES_DATA_DIR` to katalog nadrzędny. W środku PostgreSQL przechowuje dane w `<wersja>/docker`. Katalog zawierający już `PG_VERSION` bezpośrednio w katalogu głównym ma inny układ. Przy przejściu z takiej instalacji użyj nowego katalogu i odtwórz dane z kopii.

## Wariant podstawowy

```sh
docker compose up -d --build
```

W DaVinci Resolve otwórz **Project Manager → Network**. Użyj adresu ustawionego w `POSTGRES_BIND_IP` oraz loginu i hasła PostgreSQL. Stack wystawia port TCP **5432** zarówno na hoście, jak i w kontenerze. Na różnych hostach możesz używać tego samego portu. Dwie instancje na jednym hoście używają osobnych adresów IP, nazw projektu Compose i katalogów danych.

pgAdmin jest dostępny domyślnie na `http://127.0.0.1:3001` na hoście. Po utworzeniu biblioteki w Resolve wpisz jej nazwę w `BACKUP_DATABASES` i zastosuj zmianę poleceniem `docker compose up -d pgbackups`. Kopię możesz też uruchomić od razu przez `docker compose exec pgbackups /backup.sh`. Archiwa trafiają do `BACKUP_DIR` jako pliki `.backup`. Kopia pojedynczej biblioteki obejmuje jej dane. Role PostgreSQL wymagają osobnej kopii.

## Wariant z panelem WWW

Uruchom najpierw wariant podstawowy i utwórz lub odtwórz bibliotekę w Resolve. Po stronie hosta z Dockerem uruchom poniższe polecenia. Zastąp `moja_biblioteka` dokładną nazwą bazy. Skrypt możesz wywołać ponownie z kolejnymi nazwami.

```sh
python3 panel/configure.py init --db-host postgres --title 'DaVinci Project Manager' --output panel/.env

PANEL_ENV_FILE=.env \
  PANEL_POSTGRES_CONTAINER="$(docker compose ps -q postgres)" \
  PANEL_POSTGRES_ADMIN="$(docker compose exec -T postgres printenv POSTGRES_USER)" \
  sh panel/install-db.sh moja_biblioteka

docker compose -f docker-compose.yml -f compose.panel.yml up -d --build
```

Otwórz `http://127.0.0.1:3012` na hoście i zaloguj się wartością `PANEL_ADMIN_PASSWORD` z `panel/.env`, zostawiając pole loginu puste. Zachowaj ten plik przy aktualizacjach. `PANEL_BIND_IP` i `PANEL_PORT` w głównym `.env` ustawiają adres i port interfejsu. Przy udostępnianiu przez proxy HTTPS ustaw `PANEL_SECURE_COOKIE=1` w `panel/.env`.

Panel i [DaVinci Project Manager na desktop](https://github.com/LukaszOn/davinci-project-manager) mogą zarządzać tymi samymi kontami, gdy korzystają z tej samej instancji i bazy rejestru. Instalator panelu używa `psql` z kontenera PostgreSQL.

## Projekt źródłowy

Fork [Docker-Davinci-Resolve-Project-Server autorstwa Elliota Matsona](https://github.com/elliotmatson/Docker-Davinci-Resolve-Project-Server). Kod jest udostępniony na licencji [MIT](LICENSE.md). Projekt jest niezależny od Blackmagic Design.
