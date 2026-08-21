# VoiceInk Build Script

Сборка [VoiceInk](https://github.com/Beingpax/VoiceInk) — опенсорсной диктовки для macOS — из исходников одной командой, без аккаунта Apple Developer. Бонусом скрипт сразу скачивает модель **Whisper Large-v3** (~2.9 ГБ), так что после первого запуска всё готово к работе.

## Что делает скрипт

1. Проверяет окружение (macOS, Apple Silicon, git, полный Xcode) и при необходимости выполняет первичную настройку Xcode.
2. Клонирует официальный репозиторий VoiceInk и собирает его через `make local` (ad-hoc подпись, сертификат разработчика не нужен).
3. Обходит известную проблему сборки whisper.cpp на свежих Xcode: если сборка из исходников падает (или в системе нет cmake), автоматически подкладывает готовый `whisper.xcframework` из официальных релизов whisper.cpp.
4. Устанавливает готовый VoiceInk.app в `/Applications`.
5. Скачивает модель `ggml-large-v3.bin` прямо в папку моделей VoiceInk (с докачкой после обрыва и проверкой SHA-1) — приложение увидит её как установленную.

## Требования

- Mac на Apple Silicon (на M-серии сборка проверялась; Intel — на свой страх и риск)
- Полный **Xcode** из App Store (одних Command Line Tools недостаточно)
- ~7 ГБ свободного места (зависимости, сборка, модель)

## Использование

Скачайте скрипт и запустите:

```bash
curl -fsSLO https://raw.githubusercontent.com/ithouse-pro/voiceink-build/main/build-voiceink.sh
bash build-voiceink.sh
```

*(или скачайте [build-voiceink.sh](https://github.com/ithouse-pro/voiceink-build/blob/main/build-voiceink.sh) со страницы репозитория и запустите `bash build-voiceink.sh` из папки загрузок)*

Пароль скрипт спросит один раз — для первичной настройки Xcode. Первая сборка занимает 5–15 минут плюс загрузка модели.

## После установки

1. Выдайте разрешения: System Settings → Privacy & Security → **Microphone** и **Accessibility** → включить для VoiceInk.
2. В VoiceInk: **AI Models → Local** → у модели Large v3 нажмите **Set as Default**.
3. Назначьте хоткей диктовки в настройках — и проверьте в любом текстовом поле.

## Обновление

Локальная сборка не получает автообновлений: внутри собранного `VoiceInk.app` нет механизма проверки версий. Обновление — это повторный запуск того же скрипта:

```bash
bash build-voiceink.sh
```

Что он делает:

1. `git pull` в `~/VoiceInk-Build` — подтягивает свежие исходники VoiceInk с GitHub.
2. Сравнивает текущий коммит со штампом `~/VoiceInk-Build/.installed-commit` — записью о том, из какого коммита собрано приложение, лежащее в `/Applications`. Штамп ставится только после успешной установки, поэтому упавшая сборка не выдаст себя за установленную.
3. Совпало и приложение на месте — скрипт сообщает «Обновлений нет» и выходит за пару секунд, ничего не трогая. Не совпало — пересобирает и переустанавливает: 10–20 минут.

Модель Whisper при обновлении заново не качается: модели и настройки живут отдельно от приложения, в `~/Library/Application Support/com.prakashjoshipax.VoiceInk/`, а туда скрипт при пересборке не лезет.

Принудительная пересборка того же коммита — например, после обновления Xcode или если приложение повредилось:

```bash
bash build-voiceink.sh --force
```

### Проверить обновления, не запуская сборку

```bash
git -C ~/VoiceInk-Build fetch -q && git -C ~/VoiceInk-Build log --oneline HEAD..origin/main
```

Пусто — обновлений нет. Список коммитов — есть что ставить.

Посмотреть, из чего собрана установленная копия и что лежит в исходниках сейчас:

```bash
cat ~/VoiceInk-Build/.installed-commit   # коммит установленного /Applications/VoiceInk.app
git -C ~/VoiceInk-Build rev-parse HEAD   # коммит в исходниках
```

### Разрешения после пересборки

Без сертификата разработчика `make local` подписывает приложение ad-hoc — официальный [BUILDING.md](https://github.com/Beingpax/VoiceInk/blob/main/BUILDING.md) прямо предупреждает, что после такой пересборки macOS может заново потребовать разрешения. Если после обновления диктовка перестала вставлять текст, проверьте System Settings → Privacy & Security → **Accessibility** и **Microphone**.

Чтобы подпись перестала меняться от сборки к сборке, добавьте в Xcode → Settings → Accounts бесплатный Apple ID: в связке ключей появится identity `Apple Development`, и `make local` подхватит её автоматически — разрешения переживут обновление. Проверить, есть ли identity:

```bash
security find-identity -v -p codesigning
```

Если подходящих identity несколько, `make local` не угадывает и уходит в ad-hoc; нужную задают явно — `make local LOCAL_CODESIGN_IDENTITY="<SHA или имя>"`.

## Известные грабли

- **Сборка падает на `Validate plug-in "CudaBuild" in package "mlx-swift"`.** VoiceInk использует Swift-пакеты с build-плагинами, а xcodebuild из терминала не запускает их без одобрения. Скрипт включает разрешение автоматически; если собираете руками:
  ```bash
  defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
  ```
  и повторите `make local`. (Опечатка «Validatation» — так называется сам ключ Apple.)
- **Сборка падает на `cannot execute tool 'metal' due to missing Metal Toolchain`.** В Xcode 26+ компилятор Metal — отдельный загружаемый компонент, а зависимость mlx-swift компилирует Metal-шейдеры. Скрипт скачивает компонент автоматически; вручную: `xcodebuild -downloadComponent MetalToolchain` (или Xcode → Settings → Components), затем повторить `make local`. Загрузка занимает несколько гигабайт.
- **Whisper переводит русскую речь на английский.** Язык транскрипции в VoiceInk по умолчанию — English, а Whisper при английском языке вывода не транскрибирует, а переводит. Смените язык: **AI Models → Language → Russian** (или Auto-detect). Если пользуетесь Modes — у каждого режима свой языковой параметр, проверьте и его.
- **Обрывы при клонировании зависимостей** (`curl 56 Connection reset` / `curl 92 HTTP/2 stream not closed`) — проблема канала до GitHub, не скрипта. Помогает перевод git на HTTP/1.1 и повтор:
  ```bash
  git config --global http.version HTTP/1.1
  rm -rf ~/VoiceInk-Build/.local-build/SourcePackages
  cd ~/VoiceInk-Build && make local
  ```
- **`git ls-remote` может показать, что обновлений нет, когда они есть.** Ответ на запрос `HEAD` к репозиторию иногда приходит из кэша GitHub и отстаёт на дни. Проверяйте обновления только через `fetch`, как в разделе [Обновление](#обновление):
  ```bash
  git -C ~/VoiceInk-Build fetch -q && git -C ~/VoiceInk-Build log --oneline HEAD..origin/main
  ```
- **Первый запуск после обновления самого скрипта всегда пересобирает.** В ранних версиях скрипта штампа `.installed-commit` не было, поэтому новая версия не знает, из какого коммита собрана уже установленная копия, и на всякий случай пересобирает. Дальше сверка работает штатно. Если вы уверены, что установленное приложение собрано из текущих исходников, штамп можно поставить руками и сэкономить одну пересборку:
  ```bash
  git -C ~/VoiceInk-Build rev-parse HEAD > ~/VoiceInk-Build/.installed-commit
  ```

## Дисклеймер

Скрипт не аффилирован с разработчиком VoiceInk — это просто автоматизация официальной инструкции [BUILDING.md](https://github.com/Beingpax/VoiceInk/blob/main/BUILDING.md). Если сборка вам зашла — у автора VoiceInk можно купить [готовый бинарник](https://tryvoiceink.com/?atp=LQCqu0) (партнёрская ссылка), поддержав проект.

Лицензия: MIT.
