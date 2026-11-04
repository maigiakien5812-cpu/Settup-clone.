#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  SETUP CLONE APK - chạy trong Termux trên UGPhone (có root)
#  - Cài gói cần thiết cho Termux
#  - Hỏi số clone, tải 1.apk -> N.apk từ GitHub, cài im lặng bằng root
#  - Chỉnh độ rộng nhỏ nhất (smallest width) của máy lên 750
#  - Hỏi và nhập trực tiếp cookie .ROBLOSECURITY cho từng clone
# ============================================================

# ---------- CHỈ SỬA 3 DÒNG NÀY ----------
GH_USER="maigiakien5812-cpu"   # tên tài khoản GitHub
GH_REPO="Settup-clone."        # tên repo chứa file APK (có dấu chấm cuối)
GH_TAG="apk"                   # tên tag của Release chứa 1.apk, 2.apk, ...
# ----------------------------------------

TARGET_SW=750
PACKAGES="curl wget git python nano tsu"
BASE_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/${GH_TAG}"
WORK="$HOME/clone_apks"
TMP_ROOT="/data/local/tmp/clone_apks"
LOG="$WORK/setup.log"

# Key Banana: để trống thì script sẽ hỏi lúc chạy.
BANANA_KEY=""
CONFIG_NAME="config kaitun banana.txt"

GRN='\033[1;32m'; YLW='\033[1;33m'; RED='\033[1;31m'; RST='\033[0m'
say()  { printf "%b[+]%b %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%b[!]%b %s\n" "$YLW" "$RST" "$*"; }
err()  { printf "%b[x]%b %s\n" "$RED" "$RST" "$*"; }

# Chạy lệnh bằng root (không đọc stdin để khỏi nuốt mất script khi chạy qua curl | bash)
rsu() { $SU -c "$1" </dev/null 2>&1; }

# Cài 1 file apk im lặng bằng root; trả về 0 nếu thành công
install_apk() {
  local f="$1" i="$2" out size
  out=$(rsu "mkdir -p '$TMP_ROOT' && cp '$f' '$TMP_ROOT/$i.apk' && chmod 644 '$TMP_ROOT/$i.apk' && pm install -r -g '$TMP_ROOT/$i.apk'")
  echo "[$i.apk] $out" >> "$LOG"
  if echo "$out" | grep -q 'Success'; then
    rsu "rm -f '$TMP_ROOT/$i.apk'" >/dev/null
    return 0
  fi
  # Cách dự phòng: đẩy file qua stdin
  size=$(stat -c%s "$f")
  out=$($SU -c "pm install -r -g -S $size" < "$f" 2>&1)
  echo "[$i.apk - stdin] $out" >> "$LOG"
  rsu "rm -f '$TMP_ROOT/$i.apk'" >/dev/null
  echo "$out" | grep -q 'Success'
}

# Tạo Delta/Autoexecute/<config>.txt ở bộ nhớ trong
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

# Viết script python ghi cookie vào file Cookies (SQLite) của WebView
write_cookie_script() {
  cat > "$WORK/inject_cookie.py" <<'PY'
import sqlite3, sys, time
db, cookie = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
cur = con.cursor()
cols = cur.execute("PRAGMA table_info(cookies)").fetchall()
if not cols:
    print("NOTABLE")
    sys.exit(0)
now = int((time.time() + 11644473600) * 1000000)
exp = now + 365 * 24 * 3600 * 1000000
known = {
    "creation_utc": now, "host_key": ".roblox.com", "name": ".ROBLOSECURITY",
    "value": cookie, "encrypted_value": b"", "path": "/", "expires_utc": exp,
    "is_secure": 1, "is_httponly": 1, "last_access_utc": now, "has_expires": 1,
    "is_persistent": 1, "priority": 1, "samesite": -1, "source_scheme": 2,
    "source_port": 443, "last_update_utc": now, "top_frame_site_key": "",
    "source_type": 0, "has_cross_site_ancestor": 0,
}
names, vals = [], []
for cid, n, t, notnull, dflt, pk in cols:
    if n in known:
        names.append(n); vals.append(known[n])
    elif notnull and dflt is None:
        names.append(n); vals.append(0 if "INT" in (t or "").upper() else "")
cur.execute("DELETE FROM cookies WHERE name = '.ROBLOSECURITY'")
cur.execute("INSERT INTO cookies (%s) VALUES (%s)" % (",".join(names), ",".join("?" * len(names))), vals)
con.commit()
row = cur.execute("SELECT value FROM cookies WHERE name = '.ROBLOSECURITY'").fetchone()
print("OK" if row and row[0] == cookie else "FAIL")
con.close()
PY
}

# Ghi cookie vào 1 clone. Trả về: 0 = ok, 1 = lỗi ghi, 2 = không thấy file Cookies
inject_cookie() {
  local pkg="$1" cookie="$2" i="$3"
  local dir="/data/data/$pkg" db="/data/data/$pkg/app_webview/Default/Cookies"
  local tmp="$WORK/cookies_$i.db" res uid gid
  
  rsu "am force-stop $pkg" >/dev/null
  
  if ! rsu "[ -f '$db' ] && echo yes" | grep -q yes; then
    # Chưa có file Cookies: mở app 1 lần cho Android tạo thư mục WebView rồi tắt
    rsu "monkey -p $pkg -c android.intent.category.LAUNCHER 1" >/dev/null
    sleep 10
    rsu "am force-stop $pkg" >/dev/null
    sleep 1
  fi
  
  if ! rsu "[ -f '$db' ] && echo yes" | grep -q yes; then
    echo "[login $i] không thấy $db" >>"$LOG"
    return 2
  fi
  
  rm -f "$tmp"
  rsu "cp '$db' '$tmp' && chown $(id -u):$(id -g) '$tmp' && chmod 600 '$tmp'" >>"$LOG"
  res=$(python "$WORK/inject_cookie.py" "$tmp" "$cookie" </dev/null 2>>"$LOG")
  echo "[login $i] python: $res" >>"$LOG"
  
  if [ "$res" != "OK" ]; then rm -f "$tmp"; return 1; fi
  
  # Lấy UID/GID chuẩn của app để gán lại quyền cho file DB
  uid=$(rsu "stat -c %u '$dir'" | grep -oE '[0-9]+' | head -1)
  gid=$(rsu "stat -c %g '$dir'" | grep -oE '[0-9]+' | head -1)
  [ -z "$uid" ] && uid="10000"
  [ -z "$gid" ] && gid="10000"
  
  # Xóa sạch DB cũ + file WAL/SHM để Android không khôi phục lại data cũ
  rsu "rm -f '$db' '$db-journal' '$db-wal' '$db-shm'" >>"$LOG"
  rsu "cp '$tmp' '$db'" >>"$LOG"
  rsu "chown $uid:$gid '$db' && chmod 600 '$db'" >>"$LOG"
  rsu "restorecon '$db'" >/dev/null
  rm -f "$tmp"
  
  # Bật lại app để nó tự load cookie
  rsu "monkey -p $pkg -c android.intent.category.LAUNCHER 1" >/dev/null
  return 0
}

# Vòng lặp hỏi và nhập cookie trực tiếp
inject_cookies_interactive() {
  local i pkg raw_cookie cookie count_ok=0 count_skip=0
  echo ""
  say "=== NHẬP COOKIE CHO TỪNG CLONE ==="
  say "Dán cookie vào rồi Enter. Bỏ trống + Enter để bỏ qua clone đó."
  echo
  
  for i in "${OK_LIST[@]}"; do
    pkg="${PKG_MAP[$i]:-}"
    if [ -z "$pkg" ]; then
      warn "Không rõ package của clone $i, bỏ qua."
      continue
    fi
    
    printf "[Clone %s - %s]\n" "$i" "$pkg"
    printf "Cookie: "
    read -r raw_cookie </dev/tty
    
    # Lọc lấy chuỗi cookie chuẩn (đề phòng dán kèm chữ thừa)
    cookie=$(printf '%s' "$raw_cookie" | grep -o '_|WARNING.*' | head -1)
    [ -z "$cookie" ] && cookie="$raw_cookie"
    cookie=$(printf '%s' "$cookie" | tr -cd 'A-Za-z0-9_|.:+/=-')
    
    if [ "${#cookie}" -lt 100 ]; then
      if [ -n "$raw_cookie" ]; then
        warn "Cookie không hợp lệ hoặc quá ngắn. Bỏ qua clone $i."
      else
        say "Bỏ qua clone $i."
      fi
      count_skip=$((count_skip+1))
      continue
    fi
    
    printf "Đang ghi cookie vào %s ... " "$pkg"
    inject_cookie "$pkg" "$cookie" "$i"; rc=$?
    case $rc in
      0) echo "OK"; count_ok=$((count_ok+1)) ;;
      2) echo "không thấy file Cookies"; count_skip=$((count_skip+1)) ;;
      *) echo "lỗi ghi"; count_skip=$((count_skip+1)) ;;
    esac
    echo
  done
  
  if [ "$count_ok" -gt 0 ]; then
    LOGIN_MSG="Login Roblox: Đã ghi cookie thành công $count_ok/${#OK_LIST[@]} clone."
  else
    LOGIN_MSG="Login Roblox: Không ghi được cookie nào."
  fi
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
  pkg upgrade -y -o Dpkg::Options::="--force-confold" </dev/null >>"$LOG" 2>&1 \
    || warn "pkg upgrade lỗi (xem $LOG)"
  pkg install -y -o Dpkg::Options::="--force-confold" $PACKAGES </dev/null >>"$LOG" 2>&1 \
    || warn "Có gói cài lỗi (xem $LOG)"
  pkg install -y aapt </dev/null >>"$LOG" 2>&1 || true

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

  # Hỏi key Banana ngay từ đầu để mày khỏi phải ngồi chờ
  if [ -z "$BANANA_KEY" ]; then
    printf "Nhập key Banana (Enter = bỏ qua, không tạo file config): "
    read -r BANANA_KEY </dev/tty
  fi
  BANANA_KEY=$(printf '%s' "$BANANA_KEY" | tr -cd 'A-Za-z0-9_-')

  # ---------- 3c. Cài QuickBubble (bắt buộc, luôn chạy) ----------
  echo
  QB_MSG="QuickBubble: chưa cài"
  qb="$WORK/QuickBubble.apk"
  printf "Tải QuickBubble.apk ... "
  code=$(curl -sL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$qb" -w '%{http_code}' "$BASE_URL/QuickBubble.apk" </dev/null)
  if [ "$code" != "200" ] || [ ! -s "$qb" ]; then
    rm -f "$qb"
    echo "lỗi tải (HTTP $code)"
    QB_MSG="QuickBubble: LỖI TẢI (HTTP $code), kiểm tra đã up QuickBubble.apk lên Release chưa"
  else
    printf "xong, đang cài ... "
    if install_apk "$qb" "QuickBubble"; then
      echo "OK"
      QB_MSG="QuickBubble: đã cài"
      rm -f "$qb"
    else
      echo "lỗi cài"
      QB_MSG="QuickBubble: LỖI CÀI (xem $LOG)"
    fi
  fi

  # ---------- 4. Tải + cài từng clone ----------
  OK_LIST=(); FAIL_LIST=(); STOPPED_AT=""; PKG_MAP=()
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
    before=$(rsu "pm list packages" | tr -d '\r' | sort)
    if install_apk "$f" "$i"; then
      after=$(rsu "pm list packages" | tr -d '\r' | sort)
      pkgname=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed 's/^package://' | head -1)
      if [ -z "$pkgname" ] && command -v aapt >/dev/null 2>&1; then
        pkgname=$(aapt dump badging "$f" </dev/null 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)
      fi
      PKG_MAP[$i]="$pkgname"
      echo "[clone $i] package=${pkgname:-?}" >>"$LOG"
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

  # ---------- 4c. Đăng nhập Roblox bằng cookie ----------
  LOGIN_MSG="Login Roblox: bỏ qua (không có clone nào cài thành công)"
  if [ ${#OK_LIST[@]} -gt 0 ]; then
    write_cookie_script
    inject_cookies_interactive
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
  echo "  $QB_MSG"
  echo "  $DELTA_MSG"
  echo "  $LOGIN_MSG"
  echo "  $DENSITY_MSG"
  echo "  Muốn trả lại mặc định: su -c \"wm density reset\""
  echo "=================================================="
}

main "$@"
