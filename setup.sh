#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
#  SETUP CLONE APK - chạy trong Termux trên UGPhone (có root)
#  - Cài gói cần thiết cho Termux
#  - Hỏi số clone, tải 1.apk -> N.apk từ GitHub, cài im lặng bằng root
#  - Chỉnh độ rộng nhỏ nhất (smallest width) của máy lên 750
#  - Tự động khởi tạo DB cho app, nhận danh sách cookie và phân bổ
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

BANANA_KEY=""
CONFIG_NAME="config kaitun banana.txt"

GRN='\033[1;32m'; YLW='\033[1;33m'; RED='\033[1;31m'; RST='\033[0m'
say()  { printf "%b[+]%b %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%b[!]%b %s\n" "$YLW" "$RST" "$*"; }
err()  { printf "%b[x]%b %s\n" "$RED" "$RST" "$*"; }

rsu() { $SU -c "$1" </dev/null 2>&1; }

install_apk() {
  local f="$1" i="$2" out size
  out=$(rsu "mkdir -p '$TMP_ROOT' && cp '$f' '$TMP_ROOT/$i.apk' && chmod 644 '$TMP_ROOT/$i.apk' && pm install -r -g '$TMP_ROOT/$i.apk'")
  echo "[$i.apk] $out" >> "$LOG"
  if echo "$out" | grep -q 'Success'; then
    rsu "rm -f '$TMP_ROOT/$i.apk'" >/dev/null
    return 0
  fi
  size=$(stat -c%s "$f")
  out=$($SU -c "pm install -r -g -S $size" < "$f" 2>&1)
  echo "[$i.apk - stdin] $out" >> "$LOG"
  rsu "rm -f '$TMP_ROOT/$i.apk'" >/dev/null
  echo "$out" | grep -q 'Success'
}

make_delta_config() {
  local stage="$WORK/delta_stage" base ok=1
  rm -rf "$stage"; mkdir -p "$stage"
  cat > "$stage/$CONFIG_NAME" <<LUA
repeat wait() until game:IsLoaded() and game.Players.LocalPlayer
getgenv().Key = "${BANANA_KEY}"
getgenv().__BANANA_SCRIPT_ROUTE = "kaigod"
Config = {
    Team = "Pirates", FastTween = true, AutoHop = true, HopWhenIdle = true,
    FpsBoost = true, FpsCap = 25, BlockAcc = true, BlackScreen = false,
    CursedDualKatana = false, SoulGuitar = false, FarmBoneForx2EXP = false,
    WebhookEnabled = false, WebhookUrl = "", WebhookIntervalMinutes = 5
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

# Check xem cookie còn sống hay không (HTTP 200 là sống)
check_cookie_alive() {
  local ck="$1"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -H "Cookie: .ROBLOSECURITY=$ck" -H "User-Agent: Mozilla/5.0" --connect-timeout 10 "https://users.roblox.com/v1/users/authenticated")
  if [ "$code" = "200" ]; then
    return 0
  else
    return 1
  fi
}

# Tự động mở app dưới nền và dùng lệnh find để quét chuẩn xác vị trí file Cookies
init_apps_data() {
  local i pkg db wait_time act
  echo ""
  say "=== KHỞI TẠO DỮ LIỆU BAN ĐẦU CHO CÁC CLONE ==="
  for i in "${OK_LIST[@]}"; do
    pkg="${PKG_MAP[$i]:-}"
    [ -z "$pkg" ] && continue
    
    db=$(rsu "find /data/data/$pkg -type f -name 'Cookies' 2>/dev/null" | head -1)
    if [ -n "$db" ]; then
      DB_MAP[$i]="$db"
      continue
    fi
    
    printf "[Clone %s] Đang lấy data ngầm (chờ tối đa 15s) ... " "$i"
    
    act=$(rsu "cmd package resolve-activity --brief $pkg | tail -n 1")
    # Bỏ -W để không block script
    if [ -n "$act" ] && [[ "$act" == *"/"* ]]; then
      rsu "am start -n '$act'" >/dev/null 2>&1
    else
      rsu "monkey -p $pkg -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
    fi
    
    wait_time=0
    while [ $wait_time -lt 15 ]; do
      db=$(rsu "find /data/data/$pkg -type f -name 'Cookies' 2>/dev/null" | head -1)
      if [ -n "$db" ]; then break; fi
      sleep 1
      wait_time=$((wait_time+1))
    done
    
    rsu "am force-stop $pkg" >/dev/null 2>&1
    sleep 1
    
    if [ -n "$db" ]; then
      DB_MAP[$i]="$db"
      echo "OK"
    else
      echo "Thất bại (Sẽ thử tìm lại lúc ghi cookie)"
    fi
  done
}

# Chỉ ghi file DB, KHÔNG bật app lúc này để tránh app nổi đè Termux
inject_cookie_db() {
  local pkg="$1" cookie="$2" i="$3"
  local dir="/data/data/$pkg" db="${DB_MAP[$i]:-}"
  local tmp="$WORK/cookies_$i.db" res uid gid
  
  if [ -z "$db" ] || ! rsu "[ -f '$db' ] && echo yes" | grep -q yes; then
    db=$(rsu "find /data/data/$pkg -type f -name 'Cookies' 2>/dev/null" | head -1)
  fi

  if [ -z "$db" ] || ! rsu "[ -f '$db' ] && echo yes" | grep -q yes; then
    echo "[login $i] không thấy file Cookies của $pkg" >>"$LOG"
    return 2
  fi
  
  rsu "am force-stop $pkg" >/dev/null
  sleep 1
  rm -f "$tmp"
  rsu "cp '$db' '$tmp' && chown $(id -u):$(id -g) '$tmp' && chmod 600 '$tmp'" >>"$LOG"
  res=$(python "$WORK/inject_cookie.py" "$tmp" "$cookie" </dev/null 2>>"$LOG")
  
  if [ "$res" != "OK" ]; then rm -f "$tmp"; return 1; fi
  
  uid=$(rsu "stat -c %u '$dir'" | grep -oE '[0-9]+' | head -1)
  gid=$(rsu "stat -c %g '$dir'" | grep -oE '[0-9]+' | head -1)
  [ -z "$uid" ] && uid="10000"
  [ -z "$gid" ] && gid="10000"
  
  rsu "rm -f '$db' '$db-journal' '$db-wal' '$db-shm'" >>"$LOG"
  rsu "cp '$tmp' '$db'" >>"$LOG"
  rsu "chown $uid:$gid '$db' && chmod 600 '$db'" >>"$LOG"
  rsu "restorecon '$db'" >/dev/null
  rm -f "$tmp"
  return 0
}

# Hàm bật lại app sau khi đã ghi xong hết, bật từng cái một
open_apps_final() {
  local i pkg act
  echo ""
  say "=== BẬT LẠI CÁC APP ĐỂ LOAD COOKIE ==="
  for i in "${OK_LIST[@]}"; do
    pkg="${PKG_MAP[$i]:-}"
    [ -z "$pkg" ] && continue
    printf "[Clone %s] Bật app ... " "$i"
    act=$(rsu "cmd package resolve-activity --brief $pkg | tail -n 1")
    if [ -n "$act" ] && [[ "$act" == *"/"* ]]; then
      rsu "am start -n '$act'" >/dev/null 2>&1
    else
      rsu "monkey -p $pkg -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
    fi
    sleep 2
    echo "OK"
  done
}

inject_cookies_interactive() {
  local line c count=0 idx=0 raw_input="" empty_count=0
  local COOKIES=()
  
  echo ""
  say "=== NHẬP COOKIE HÀNG LOẠT ==="
  say "Dán danh sách cookie vào (kể cả bị xuống dòng do dài)."
  say "Dán xong, ấn Enter 2 lần (tạo 1 dòng trống) để bắt đầu chạy."
  echo
  
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(printf '%s' "$line" | tr -d '\r')
    
    if [ -z "$line" ]; then
      empty_count=$((empty_count+1))
      if [ "$empty_count" -ge 2 ]; then break; fi
    else
      empty_count=0
    fi
    
    raw_input+="$line"
  done </dev/tty
  
  raw_input=$(printf '%s' "$raw_input" | sed 's/_|WARNING/\n_|WARNING/g')
  
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    c=$(printf '%s' "$line" | tr -cd 'A-Za-z0-9_|.:+/=-')
    
    if [ "${#c}" -ge 100 ]; then
      COOKIES+=("$c")
      say "Đã nhận cookie thứ ${#COOKIES[@]}"
    else
      warn "Bỏ qua đoạn code rác (dài ${#c} ký tự)."
    fi
  done <<< "$raw_input"
  
  if [ ${#COOKIES[@]} -eq 0 ]; then
    warn "Không có cookie nào hợp lệ."
    LOGIN_MSG="Login Roblox: Không nhập được cookie."
    return
  fi
  
  # 1. CHECK SỐNG CHẾT
  echo ""
  say "=== CHECK SỐNG/CHẾT CỦA COOKIE ==="
  local valid_cookies=()
  for ck in "${COOKIES[@]}"; do
    printf "Check cookie ... "
    if check_cookie_alive "$ck"; then
      echo "SỐNG"
      valid_cookies+=("$ck")
    else
      echo "CHẾT (Bỏ qua)"
    fi
  done
  
  if [ ${#valid_cookies[@]} -eq 0 ]; then
    err "Toàn bộ cookie đều chết. Dừng lại."
    LOGIN_MSG="Login Roblox: Toàn bộ cookie chết."
    return
  fi
  
  # 2. GHI DB
  say "Bắt đầu ghi cookie vào các clone..."
  echo
  
  local count_ok=0 count_fail=0
  for i in "${OK_LIST[@]}"; do
    if [ "$idx" -ge "${#valid_cookies[@]}" ]; then
      warn "Đã hết cookie sống để gán cho clone $i."
      count_fail=$((count_fail+1))
      continue
    fi
    
    pkg="${PKG_MAP[$i]:-}"
    ck="${valid_cookies[$idx]}"
    idx=$((idx+1))
    
    printf "[Clone %s - %s] Đang ghi cookie ... " "$i" "$pkg"
    inject_cookie_db "$pkg" "$ck" "$i"; rc=$?
    case $rc in
      0) echo "OK"; count_ok=$((count_ok+1)) ;;
      2) echo "Không thấy DB"; count_fail=$((count_fail+1)) ;;
      *) echo "Lỗi ghi"; count_fail=$((count_fail+1)) ;;
    esac
  done
  
  LOGIN_MSG="Login Roblox: Đã ghi thành công $count_ok/${#OK_LIST[@]} clone (nhận ${#valid_cookies[@]} cookie sống)."
  
  # 3. BẬT APP
  open_apps_final
}

main() {
  mkdir -p "$WORK"
  : > "$LOG"

  if [ "$GH_USER" = "TEN_GITHUB" ] || [ "$GH_REPO" = "TEN_REPO" ]; then
    err "Chưa sửa GH_USER / GH_REPO ở đầu file setup.sh."
    return 1
  fi

  SU=""
  for p in su /system/xbin/su /system/bin/su /sbin/su /su/bin/su; do
    if command -v "$p" >/dev/null 2>&1; then SU="$p"; break; fi
  done
  if [ -z "$SU" ] || ! $SU -c id </dev/null 2>/dev/null | grep -q 'uid=0'; then
    err "Không lấy được root."
    return 1
  fi
  say "Đã có root."

  say "Đang cập nhật Termux và cài gói: $PACKAGES..."
  export DEBIAN_FRONTEND=noninteractive
  pkg update -y -o Dpkg::Options::="--force-confold" </dev/null >>"$LOG" 2>&1 || warn "pkg update lỗi"
  pkg upgrade -y -o Dpkg::Options::="--force-confold" </dev/null >>"$LOG" 2>&1 || warn "pkg upgrade lỗi"
  pkg install -y -o Dpkg::Options::="--force-confold" $PACKAGES </dev/null >>"$LOG" 2>&1 || warn "Có gói cài lỗi"
  pkg install -y aapt </dev/null >>"$LOG" 2>&1 || true

  if ! curl --version >/dev/null 2>&1; then
    err "curl bị hỏng. Chạy: pkg update -y && pkg upgrade -y rồi thử lại."
    return 1
  fi

  echo
  while true; do
    printf "Bạn muốn tải bao nhiêu clone? (nhập số): "
    read -r COUNT </dev/tty
    if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -ge 1 ]; then break; fi
    warn "Nhập số nguyên từ 1 trở lên nhé."
  done

  if [ -z "$BANANA_KEY" ]; then
    printf "Nhập key Banana (Enter = bỏ qua): "
    read -r BANANA_KEY </dev/tty
  fi
  BANANA_KEY=$(printf '%s' "$BANANA_KEY" | tr -cd 'A-Za-z0-9_-')

  echo
  QB_MSG="QuickBubble: chưa cài"
  qb="$WORK/QuickBubble.apk"
  printf "Tải QuickBubble.apk ... "
  code=$(curl -sL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$qb" -w '%{http_code}' "$BASE_URL/QuickBubble.apk" </dev/null)
  if [ "$code" != "200" ] || [ ! -s "$qb" ]; then
    rm -f "$qb"; echo "lỗi tải (HTTP $code)"; QB_MSG="QuickBubble: LỖI TẢI"
  else
    printf "xong, đang cài ... "
    if install_apk "$qb" "QuickBubble"; then
      echo "OK"; QB_MSG="QuickBubble: đã cài"; rm -f "$qb"
    else
      echo "lỗi cài"; QB_MSG="QuickBubble: LỖI CÀI"
    fi
  fi

  OK_LIST=(); FAIL_LIST=(); STOPPED_AT=""; PKG_MAP=()
  declare -A DB_MAP=()
  
  echo
  for ((i=1; i<=COUNT; i++)); do
    f="$WORK/$i.apk"; url="$BASE_URL/$i.apk"
    printf "[%s/%s] Tải %s.apk ... " "$i" "$COUNT" "$i"
    code=$(curl -sL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$f" -w '%{http_code}' "$url" </dev/null)

    if [ "$code" = "404" ]; then
      rm -f "$f"; echo "không có file"; STOPPED_AT="$i"; break
    elif [ "$code" != "200" ] || [ ! -s "$f" ]; then
      rm -f "$f"; echo "lỗi tải (HTTP $code)"; FAIL_LIST+=("$i (tải lỗi)"); continue
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
      echo "OK"; OK_LIST+=("$i"); rm -f "$f"
    else
      echo "lỗi cài"; FAIL_LIST+=("$i (cài lỗi)")
    fi
  done

  DELTA_MSG="Config Delta: bỏ qua (không nhập key)"
  if [ -n "$BANANA_KEY" ]; then
    if make_delta_config; then DELTA_MSG="Config Delta: đã tạo"; else DELTA_MSG="Config Delta: TẠO LỖI"; fi
  fi

  LOGIN_MSG="Login Roblox: bỏ qua"
  if [ ${#OK_LIST[@]} -gt 0 ]; then
    write_cookie_script
    init_apps_data
    inject_cookies_interactive
  fi

  echo
  DENSITY_MSG=""
  SIZE=$(rsu "wm size" | grep -i 'physical' | grep -oE '[0-9]+x[0-9]+' | head -1)
  [ -z "$SIZE" ] && SIZE=$(rsu "wm size" | grep -oE '[0-9]+x[0-9]+' | head -1)
  if [ -n "$SIZE" ]; then
    W=${SIZE%x*}; H=${SIZE#*x}
    SMALL=$(( W < H ? W : H ))
    DPI=$(( SMALL * 160 / TARGET_SW ))
    rsu "wm density $DPI" >/dev/null
    NOW_SW=$(( SMALL * 160 / DPI ))
    DENSITY_MSG="Màn hình ${SIZE}, density ${DPI} => smallest width ≈ ${NOW_SW}dp"
  else
    DENSITY_MSG="Không đọc được kích thước màn hình."
  fi

  printf '\a'
  echo "=================================================="
  say "XONG!"
  echo "  Cài thành công : ${#OK_LIST[@]} clone"
  if [ ${#FAIL_LIST[@]} -gt 0 ]; then warn "Lỗi: ${FAIL_LIST[*]}"; fi
  echo "  $QB_MSG"
  echo "  $DELTA_MSG"
  echo "  $LOGIN_MSG"
  echo "  $DENSITY_MSG"
  echo "=================================================="
}

main "$@"
