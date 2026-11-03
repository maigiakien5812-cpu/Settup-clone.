#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  SETUP CLONE APK - chạy trong Termux trên UGPhone (có root)
#  - Cài gói cần thiết cho Termux
#  - Hỏi số clone, tải 1.apk -> N.apk từ GitHub, cài im lặng bằng root
#  - Chỉnh độ rộng nhỏ nhất (smallest width) của máy lên 750
# ============================================================

# ---------- CHỈ SỬA 3 DÒNG NÀY ----------
GH_USER="maigiakien5812-cpu"   # tên tài khoản GitHub
GH_REPO="Settup-clone."        # tên repo chứa file APK (có dấu chấm cuối)
GH_TAG="apk"             # tên tag của Release chứa 1.apk, 2.apk, ...
# ----------------------------------------

TARGET_SW=750
PACKAGES="curl wget git python nano tsu"
BASE_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/${GH_TAG}"
WORK="$HOME/clone_apks"
TMP_ROOT="/data/local/tmp/clone_apks"
LOG="$WORK/setup.log"

# Key Banana: để trống thì script sẽ hỏi lúc chạy.
# Chỉ ghi key vào đây nếu repo để PRIVATE (repo Public thì ai cũng đọc được key).
BANANA_KEY=""
CONFIG_NAME="config kaitun banana.txt"

GRN='\033[1;32m'; YLW='\033[1;33m'; RED='\033[1;31m'; RST='\033[0m'
say()  { printf "%b[+]%b %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%b[!]%b %s\n" "$YLW" "$RST" "$*"; }
err()  { printf "%b[x]%b %s\n" "$RED" "$RST" "$*"; }

# chạy lệnh bằng root (không đọc stdin để khỏi nuốt mất script khi chạy qua curl | bash)
rsu() { $SU -c "$1" </dev/null 2>&1; }

# cài 1 file apk im lặng bằng root; trả về 0 nếu thành công
install_apk() {
  local f="$1" i="$2" out size
  out=$(rsu "mkdir -p '$TMP_ROOT' && cp '$f' '$TMP_ROOT/$i.apk' && chmod 644 '$TMP_ROOT/$i.apk' && pm install -r -g '$TMP_ROOT/$i.apk'")
  echo "[$i.apk] $out" >> "$LOG"
  if echo "$out" | grep -q 'Success'; then
    rsu "rm -f '$TMP_ROOT/$i.apk'" >/dev/null
    return 0
  fi
  # cách dự phòng: đẩy file qua stdin
  size=$(stat -c%s "$f")
  out=$($SU -c "pm install -r -g -S $size" < "$f" 2>&1)
  echo "[$i.apk - stdin] $out" >> "$LOG"
  rsu "rm -f '$TMP_ROOT/$i.apk'" >/dev/null
  echo "$out" | grep -q 'Success'
}

# tạo Delta/Autoexecute/<config>.txt ở bộ nhớ trong
make_delta_config() {
  local stage="$WORK/delta_stage" base ok=1
  rm -rf "$stage"; mkdir -p "$stage"
  cat > "$stage/$CONFIG_NAME" <<LUA
repeat wait() until game:IsLoaded() and game.Players.LocalPlayer
getgenv().Key = "${BANANA_KEY}"
getgenv().__BANANA_SCRIPT_ROUTE = "kaigod"
Config = {
    Team = "Pirates",
    FastTween = true, -- low fps -> false plz
    AutoHop = true, -- hop server to collect better fruit
    HopWhenIdle = true,
    FpsBoost = true,
    FpsCap = 25,
    BlockAcc = true,
    BlackScreen = false,
    CursedDualKatana = false,
    SoulGuitar = false,
    FarmBoneForx2EXP = false,
    WebhookEnabled = false,
    WebhookUrl = "",
    WebhookIntervalMinutes = 5
}
return loadstring(game:HttpGet("https://banana-hub.xyz/loader/banana.lua"))()
LUA
  for base in /storage/emulated/0 /sdcard; do
    rsu "mkdir -p '$base/Delta/Autoexecute' && cp '$stage/$CONFIG_NAME' '$base/Delta/Autoexecute/$CONFIG_NAME'" >>"$LOG"
    if rsu "ls '$base/Delta/Autoexecute'" | grep -q "$CONFIG_NAME"; then
      DELTA_PATH="$base/Delta/Autoexecute/$CONFIG_NAME"
      ok=0
      break
    fi
  done
  rm -rf "$stage"
  return $ok
}

main() {
  mkdir -p "$WORK"
  : > "$LOG"

  if [ "$GH_USER" = "TEN_GITHUB" ] || [ "$GH_REPO" = "TEN_REPO" ]; then
    err "Chưa sửa GH_USER / GH_REPO ở đầu file setup.sh."
    return 1
  fi

  # ---------- 1. Kiểm tra root ----------
  SU=""
  for p in su /system/xbin/su /system/bin/su /sbin/su /su/bin/su; do
    if command -v "$p" >/dev/null 2>&1; then SU="$p"; break; fi
  done
  if [ -z "$SU" ] || ! $SU -c id </dev/null 2>/dev/null | grep -q 'uid=0'; then
    err "Không lấy được root. Bật root trên UGPhone rồi chạy lại (nếu hiện popup xin quyền thì bấm Cho phép)."
    return 1
  fi
  say "Đã có root."

  # ---------- 2. Cài gói cho Termux ----------
  say "Đang cập nhật Termux và cài gói: $PACKAGES (có thể mất vài phút)"
  export DEBIAN_FRONTEND=noninteractive
  pkg update -y -o Dpkg::Options::="--force-confold" </dev/null >>"$LOG" 2>&1 \
    || warn "pkg update lỗi (bỏ qua, xem $LOG)"
  # nâng cấp toàn bộ để curl / openssl không bị lệch phiên bản
  pkg upgrade -y -o Dpkg::Options::="--force-confold" </dev/null >>"$LOG" 2>&1 \
    || warn "pkg upgrade lỗi (xem $LOG)"
  pkg install -y -o Dpkg::Options::="--force-confold" $PACKAGES </dev/null >>"$LOG" 2>&1 \
    || warn "Có gói cài lỗi (xem $LOG)"

  # kiểm tra curl còn chạy được không trước khi tải APK
  if ! curl --version >/dev/null 2>&1; then
    err "curl bị hỏng sau khi cập nhật gói. Chạy: pkg update -y && pkg upgrade -y rồi chạy lại lệnh."
    return 1
  fi

  # ---------- 3. Hỏi số clone ----------
  echo
  while true; do
    printf "Bạn muốn tải bao nhiêu clone? (nhập số): "
    read -r COUNT </dev/tty
    if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -ge 1 ]; then break; fi
    warn "Nhập số nguyên từ 1 trở lên nhé."
  done

  # hỏi key Banana ngay từ đầu để mày khỏi phải ngồi chờ
  if [ -z "$BANANA_KEY" ]; then
    printf "Nhập key Banana (Enter = bỏ qua, không tạo file config): "
    read -r BANANA_KEY </dev/tty
  fi
  BANANA_KEY=$(printf '%s' "$BANANA_KEY" | tr -cd 'A-Za-z0-9_-')

  # ---------- 4. Tải + cài từng clone ----------
  OK_LIST=(); FAIL_LIST=(); STOPPED_AT=""
  echo
  for ((i=1; i<=COUNT; i++)); do
    f="$WORK/$i.apk"
    url="$BASE_URL/$i.apk"
    printf "[%s/%s] Tải %s.apk ... " "$i" "$COUNT" "$i"
    code=$(curl -sL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$f" -w '%{http_code}' "$url" </dev/null)

    if [ "$code" = "404" ]; then
      rm -f "$f"
      echo "không có file"
      if [ "$i" = "1" ]; then
        warn "Không thấy 1.apk: kiểm tra lại GH_USER / GH_REPO / GH_TAG và repo phải để Public."
      fi
      STOPPED_AT="$i"
      break
    elif [ "$code" != "200" ] || [ ! -s "$f" ]; then
      rm -f "$f"
      echo "lỗi tải (HTTP $code)"
      FAIL_LIST+=("$i (tải lỗi)")
      continue
    fi

    printf "xong, đang cài ... "
    if install_apk "$f" "$i"; then
      echo "OK"
      OK_LIST+=("$i")
      rm -f "$f"
    else
      echo "lỗi cài"
      FAIL_LIST+=("$i (cài lỗi)")
    fi
  done

  # ---------- 4b. Tạo file config Delta ----------
  DELTA_MSG="Config Delta: bỏ qua (không nhập key)"
  if [ -n "$BANANA_KEY" ]; then
    if make_delta_config; then
      DELTA_MSG="Config Delta: đã tạo $DELTA_PATH"
    else
      DELTA_MSG="Config Delta: TẠO LỖI (xem $LOG)"
    fi
  fi

  # ---------- 5. Chỉnh độ rộng nhỏ nhất ----------
  echo
  DENSITY_MSG=""
  SIZE=$(rsu "wm size" | grep -i 'physical' | grep -oE '[0-9]+x[0-9]+' | head -1)
  if [ -z "$SIZE" ]; then
    SIZE=$(rsu "wm size" | grep -oE '[0-9]+x[0-9]+' | head -1)
  fi
  if [ -n "$SIZE" ]; then
    W=${SIZE%x*}; H=${SIZE#*x}
    SMALL=$(( W < H ? W : H ))
    DPI=$(( SMALL * 160 / TARGET_SW ))
    rsu "wm density $DPI" >/dev/null
    NOW_SW=$(( SMALL * 160 / DPI ))
    DENSITY_MSG="Màn hình ${SIZE}, density đặt = ${DPI} => smallest width ≈ ${NOW_SW}dp"
  else
    DENSITY_MSG="Không đọc được kích thước màn hình, chưa chỉnh được độ rộng."
  fi

  # ---------- 6. Báo kết quả ----------
  printf '\a'
  echo "=================================================="
  say "XONG!"
  echo "  Cài thành công : ${#OK_LIST[@]} clone ${OK_LIST[*]:+(số: ${OK_LIST[*]})}"
  if [ -n "$STOPPED_AT" ]; then
    echo "  Dừng ở số $STOPPED_AT vì trên GitHub chưa có ${STOPPED_AT}.apk (bạn xin $COUNT, hiện chỉ có $((STOPPED_AT-1)) file)"
  fi
  if [ ${#FAIL_LIST[@]} -gt 0 ]; then
    warn "Lỗi: ${FAIL_LIST[*]}  (xem chi tiết: cat $LOG)"
  fi
  echo "  $DELTA_MSG"
  echo "  $DENSITY_MSG"
  echo "  Muốn trả lại mặc định: su -c \"wm density reset\""
  echo "=================================================="
}

main "$@"
