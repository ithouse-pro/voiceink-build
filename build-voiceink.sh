#!/bin/bash
# ============================================================
#  VoiceInk — автоматическая сборка из исходников (macOS)
#  Для Apple Silicon (M1/M2/M3/M4). Требуется Xcode.
#  Использование:  bash build-voiceink.sh
# ============================================================
set -u

WORKDIR="$HOME/VoiceInk-Build"
DEPS_DIR="$HOME/VoiceInk-Dependencies"
XCF_DIR="$DEPS_DIR/whisper.cpp/build-apple"
APP_OUT="$HOME/Downloads/VoiceInk.app"

msg()  { printf "\n\033[1;36m==> %s\033[0m\n" "$1"; }
ok()   { printf "\033[1;32m    ✓ %s\033[0m\n" "$1"; }
warn() { printf "\033[1;33m    ! %s\033[0m\n" "$1"; }
die()  { printf "\n\033[1;31mОШИБКА: %s\033[0m\n" "$1"; exit 1; }

# ---------- 1. Проверки окружения ----------
msg "Проверяю окружение"

[[ "$(uname)" == "Darwin" ]] || die "Этот скрипт нужно запускать на macOS."
[[ "$(uname -m)" == "arm64" ]] || warn "Обнаружен не Apple Silicon — сборка возможна, но не тестировалась."

command -v git >/dev/null 2>&1 || die "git не найден. Установите Command Line Tools:  xcode-select --install"

if ! command -v xcodebuild >/dev/null 2>&1; then
  die "Xcode не найден. Установите полный Xcode из App Store (Command Line Tools недостаточно), затем запустите скрипт снова."
fi

# Xcode должен быть выбран как активный (а не только CLT)
if ! xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  warn "Активны только Command Line Tools. Переключаю на Xcode (потребуется пароль)..."
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer || die "Не удалось переключиться на Xcode."
fi

# Лицензия и первичная настройка Xcode (лечит ошибки CoreSimulator/IDESimulatorFoundation)
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  warn "Выполняю первичную настройку Xcode (потребуется пароль)..."
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
fi
ok "Xcode готов: $(xcodebuild -version | head -1)"

# ---------- 2. Клонирование репозитория ----------
msg "Получаю исходники VoiceInk"
if [[ -d "$WORKDIR/.git" ]]; then
  git -C "$WORKDIR" pull --ff-only || warn "Не удалось обновить репозиторий, собираю текущую версию."
else
  git clone https://github.com/Beingpax/VoiceInk.git "$WORKDIR" || die "Не удалось клонировать репозиторий."
fi
ok "Исходники в $WORKDIR"

# ---------- 3. Обход известной проблемы: сборка whisper.cpp ----------
# С новыми Xcode сборка whisper.cpp из исходников через CMake может падать.
# Решение из issue #530: подложить готовый whisper.xcframework из релизов.
fetch_prebuilt_xcframework() {
  msg "Скачиваю готовый whisper.xcframework из официальных релизов whisper.cpp"
  local api_json url tmpzip tmpdir found
  api_json=$(curl -fsSL "https://api.github.com/repos/ggml-org/whisper.cpp/releases/latest") \
    || die "Не удалось обратиться к GitHub API."
  url=$(printf '%s' "$api_json" \
        | grep -oE '"browser_download_url": *"[^"]*xcframework[^"]*\.zip"' \
        | head -1 | sed -E 's/.*"(https[^"]*)"/\1/')
  [[ -n "${url:-}" ]] || die "В последнем релизе whisper.cpp не найден xcframework.zip — проверьте releases вручную."

  tmpdir=$(mktemp -d -t whisper-xcf) || die "Не удалось создать временную папку."
  tmpzip="$tmpdir/whisper-xcframework.zip"
  curl -fL --progress-bar -o "$tmpzip" "$url" || die "Не удалось скачать $url"
  unzip -q -o "$tmpzip" -d "$tmpdir/unpacked" || die "Не удалось распаковать архив."

  found=$(find "$tmpdir/unpacked" -maxdepth 4 -type d -name "whisper.xcframework" | head -1)
  [[ -n "$found" ]] || die "whisper.xcframework не найден внутри архива."

  mkdir -p "$XCF_DIR"
  rm -rf "$XCF_DIR/whisper.xcframework"
  mv "$found" "$XCF_DIR/whisper.xcframework"
  rm -rf "$tmpdir"
  ok "Готовый framework установлен в $XCF_DIR"
}

# Если нет cmake — сборка whisper из исходников невозможна, сразу берём готовый framework
if ! command -v cmake >/dev/null 2>&1; then
  warn "cmake не найден — использую готовый whisper.xcframework вместо сборки из исходников."
  fetch_prebuilt_xcframework
fi

# ---------- 4. Сборка ----------
cd "$WORKDIR" || die "Не удалось перейти в $WORKDIR"
msg "Собираю VoiceInk (make local — без сертификата Apple Developer)"
if ! make local; then
  warn "Первая попытка не удалась. Пробую обход: готовый whisper.xcframework + повторная сборка."
  fetch_prebuilt_xcframework
  make local || die "Сборка не удалась и после обхода. Пришлите мне вывод ошибки — разберём."
fi

[[ -d "$APP_OUT" ]] || APP_OUT=$(find "$WORKDIR" "$HOME/Downloads" -maxdepth 4 -type d -name "VoiceInk.app" 2>/dev/null | head -1)
[[ -n "${APP_OUT:-}" && -d "$APP_OUT" ]] || die "Сборка завершилась, но VoiceInk.app не найден."
ok "Приложение собрано: $APP_OUT"

# ---------- 5. Установка в /Applications ----------
msg "Устанавливаю в /Applications"
rm -rf "/Applications/VoiceInk.app"
if ditto "$APP_OUT" "/Applications/VoiceInk.app"; then
  ok "Установлено: /Applications/VoiceInk.app"
  APP_FINAL="/Applications/VoiceInk.app"
else
  warn "Не удалось скопировать в /Applications — приложение осталось в: $APP_OUT"
  APP_FINAL="$APP_OUT"
fi

# ---------- 6. Загрузка модели Large-v3 ----------
# VoiceInk сканирует эту папку на .bin-файлы (WhisperModelManager.loadAvailableModels),
# поэтому предзагруженная модель определится как установленная.
MODELS_DIR="$HOME/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels"
MODEL_FILE="$MODELS_DIR/ggml-large-v3.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
MODEL_SHA1="ad82bf6a9043ceed055076d0fd39f5f186ff8062"
MIN_SIZE=2900000000  # ~2.9 ГБ — защита от обрезанных загрузок

msg "Скачиваю модель Whisper Large-v3 (~2.9 ГБ — это самый долгий шаг)"
mkdir -p "$MODELS_DIR"

model_size() { stat -f%z "$MODEL_FILE" 2>/dev/null || echo 0; }

if [[ -f "$MODEL_FILE" ]] && (( $(model_size) >= MIN_SIZE )); then
  ok "Модель уже на месте: $MODEL_FILE — пропускаю загрузку."
else
  # -C - позволяет докачать файл после обрыва: просто перезапустите скрипт
  if curl -fL -C - --progress-bar -o "$MODEL_FILE" "$MODEL_URL"; then
    if (( $(model_size) >= MIN_SIZE )); then
      ok "Модель скачана: $MODEL_FILE ($(du -h "$MODEL_FILE" | cut -f1))"
      if command -v shasum >/dev/null 2>&1; then
        actual_sha=$(shasum -a 1 "$MODEL_FILE" | cut -d' ' -f1)
        if [[ "$actual_sha" == "$MODEL_SHA1" ]]; then
          ok "Контрольная сумма SHA-1 совпала — файл целый."
        else
          warn "SHA-1 не совпала с ожидаемой (файл на Hugging Face могли обновить)."
          warn "Если модель не заработает — удалите $MODEL_FILE и перезапустите скрипт."
        fi
      fi
    else
      warn "Файл модели подозрительно мал — загрузка оборвалась. Перезапустите скрипт, докачка продолжится с места обрыва."
    fi
  else
    warn "Не удалось скачать модель. Перезапустите скрипт (докачка поддерживается)"
    warn "или скачайте её позже прямо в VoiceInk: AI Models → Local → Large v3."
  fi
fi

# ---------- 7. Запуск ----------
msg "Запускаю VoiceInk"
open "$APP_FINAL"

printf "\n\033[1;32m============================================\033[0m\n"
printf "\033[1;32m  Готово! VoiceInk собран и запущен.\033[0m\n"
printf "\033[1;32m============================================\033[0m\n"
cat <<'EOF'

Дальнейшие шаги:
 1. Выдайте разрешения: System Settings → Privacy & Security →
    Microphone и Accessibility → включить для VoiceInk.
 2. В VoiceInk: AI Models → Local → у модели Large v3 нажмите
    Set as Default (она уже скачана этим скриптом).
 3. Назначьте хоткей диктовки в настройках и проверьте в любом текстовом поле.

Примечание: локальная сборка не получает автообновлений —
для обновления просто запустите этот скрипт ещё раз.
EOF
