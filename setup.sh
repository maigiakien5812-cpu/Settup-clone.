#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  SETUP CLONE APK - chạy trong Termux trên UGPhone (có root)
#  - Cài gói cần thiết cho Termux
#  - Hỏi số clone, tải 1.apk -> N.apk từ GitHub, cài im lặng bằng root
#  - Chỉnh độ rộng nhỏ nhất (smallest width) của máy lên 750
# ============================================================

# ---------- CHỈ SỬA 3 DÒNG NÀY ----------
GH_USER="maigiakien5812-cpu"   # tên tài khoản GitHub
GH_REPO="Setup-clone"          # tên repo chứa file APK
GH_TAG="apk"             # tên tag của Release chứa 1.apk, 2.apk, ...
# ----------------------------------------

TARGET_SW=750
PACKAGES="curl wget git python nano tsu"
BASE_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/${GH_TAG}"
WORK="$HOME/clone_apks"
TMP_ROOT="/data/local/tmp/clone_apks"
LOG="$WORK/setup.log"

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
  say "Đang cài gói cần thiết: $PACKAGES"
  export DEBIAN_FRONTEND=noninteractive
  pkg update -y -o Dpkg::Options::="--force-confold" </dev/null >>"$LOG" 2>&1 \
    || warn "pkg update lỗi (bỏ qua, xem $LOG)"
  pkg install -y -o Dpkg::Options::="--force-confold" $PACKAGES </dev/null >>"$LOG" 2>&1 \
    || warn "Có gói cài lỗi (xem $LOG)"

  # ---------- 3. Hỏi số clone ----------
  echo
  while true; do
    printf "Bạn muốn tải bao nhiêu clone? (nhập số): "
    read -r COUNT </dev/tty
    if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -ge 1 ]; then break; fi
    warn "Nhập số nguyên từ 1 trở lên nhé."
  done

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
  echo "  $DENSITY_MSG"
  echo "  Muốn trả lại mặc định: su -c \"wm density reset\""
  echo "=================================================="
}

main "$@"
