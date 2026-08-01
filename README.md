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
curl -fsSLO https://raw.githubusercontent.com/USERNAME/REPO/main/build-voiceink.sh
bash build-voiceink.sh
```

*(замените `USERNAME/REPO` на ваш репозиторий — или просто скачайте файл со страницы и запустите `bash build-voiceink.sh` из папки загрузок)*

Пароль скрипт спросит один раз — для первичной настройки Xcode. Первая сборка занимает 5–15 минут плюс загрузка модели.

## После установки

1. Выдайте разрешения: System Settings → Privacy & Security → **Microphone** и **Accessibility** → включить для VoiceInk.
2. В VoiceInk: **AI Models → Local** → у модели Large v3 нажмите **Set as Default**.
3. Назначьте хоткей диктовки в настройках — и проверьте в любом текстовом поле.

## Известные грабли

- **Обрывы при клонировании зависимостей** (`curl 56 Connection reset` / `curl 92 HTTP/2 stream not closed`) — проблема канала до GitHub, не скрипта. Помогает перевод git на HTTP/1.1 и повтор:
  ```bash
  git config --global http.version HTTP/1.1
  rm -rf ~/VoiceInk-Build/.local-build/SourcePackages
  cd ~/VoiceInk-Build && make local
  ```
- **Локальная сборка не получает автообновлений.** Для обновления просто запустите скрипт ещё раз — модель повторно качаться не будет.

## Дисклеймер

Скрипт не аффилирован с разработчиком VoiceInk — это просто автоматизация официальной инструкции [BUILDING.md](https://github.com/Beingpax/VoiceInk/blob/main/BUILDING.md). Если сборка вам зашла — у автора VoiceInk можно купить [готовый бинарник]([https://tryvoiceink.com)](https://tryvoiceink.com/?atp=LQCqu0), поддержав проект.

Лицензия: MIT.
