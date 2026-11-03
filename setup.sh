#!/data/data/com.termux/files/usr/bin/bash

# SETUP CLONE APK - UGPhone

GH_USER="maigiakien5812-cpu"
GH_REPO="Settup-clone."
GH_TAG="apk"

TARGET_SW=750
PACKAGES="curl wget git python nano tsu"
BASE_URL="https://github.com/${GH_USER}/${GH_REPO}/releases/download/${GH_TAG}"
WORK="$HOME/clone_apks"
TMP_ROOT="/data/local/tmp/clone_apks"
LOG="$WORK/setup.log"

GRN='\033[1;32m'
YLW='\033[1;33m'
RED='\033[1;31m'
RST='\033[0m'

say()  { printf "%b[+]%b %s\n" "$GRN" "$RST" "$*"; }
warn() { printf "%b[!]%b %s\n" "$YLW" "$RST" "$*"; }
err()  { printf "%b[x]%b %s\n" "$RED" "$RST" "$*"; }

rsu() {
    $SU -c "$1" </dev/null 2>&1
}

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

main() {
    mkdir -p "$WORK"
    : > "$LOG"

    if [ "$GH_USER" = "TEN_GITHUB" ] || [ "$GH_REPO" = "TEN_REPO" ]; then
        err "Chua sua GH_USER / GH_REPO."
        return 1
    fi

    # KIEM TRA ROOT
    SU=""

    for p in su /system/xbin/su /system/bin/su /sbin/su /su/bin/su; do
        if command -v "$p" >/dev/null 2>&1; then
            SU="$p"
            break
        fi
    done

    if [ -z "$SU" ] || ! $SU -c id </dev/null 2>/dev/null | grep -q 'uid=0'; then
        err "Khong lay duoc root. Hay bat root tren UGPhone."
        return 1
    fi

    say "Da co root."

    # CAI GOI TERMUX
    say "Dang cai goi can thiet: $PACKAGES"

    export DEBIAN_FRONTEND=noninteractive

    pkg update -y -o Dpkg::Options::="--force-confold" </dev/null >>"$LOG" 2>&1 \
        || warn "pkg update loi."

    pkg install -y -o Dpkg::Options::="--force-confold" $PACKAGES </dev/null >>"$LOG" 2>&1 \
        || warn "Co goi cai loi."

    # NHAP SO CLONE
    echo

    while true; do
        printf "Ban muon tai bao nhieu clone? (1-6): "
        read -r COUNT </dev/tty

        if [[ "$COUNT" =~ ^[0-9]+$ ]] && [ "$COUNT" -ge 1 ] && [ "$COUNT" -le 6 ]; then
            break
        fi

        warn "Nhap so tu 1 den 6."
    done

    # TAI VA CAI APK
    OK_LIST=()
    FAIL_LIST=()
    STOPPED_AT=""

    echo

    for ((i=1; i<=COUNT; i++)); do
        f="$WORK/$i.apk"
        url="$BASE_URL/$i.apk"

        printf "[%s/%s] Tai %s.apk ... " "$i" "$COUNT" "$i"

        code=$(curl -sL --retry 3 --retry-delay 2 --connect-timeout 20 \
            -o "$f" -w '%{http_code}' "$url" </dev/null)

        if [ "$code" = "404" ]; then
            rm -f "$f"
            echo "Khong co file"

            if [ "$i" = "1" ]; then
                warn "Khong thay 1.apk. Kiem tra repo, tag va quyen Public."
            fi

            STOPPED_AT="$i"
            break

        elif [ "$code" != "200" ] || [ ! -s "$f" ]; then
            rm -f "$f"
            echo "Loi tai HTTP $code"
            FAIL_LIST+=("$i (tai loi)")
            continue
        fi

        printf "Xong, dang cai ... "

        if install_apk "$f" "$i"; then
            echo "OK"
            OK_LIST+=("$i")
            rm -f "$f"
        else
            echo "Loi cai"
            FAIL_LIST+=("$i (cai loi)")
        fi
    done

    # CHINH SMALLEST WIDTH
    echo

    DENSITY_MSG=""

    SIZE=$(rsu "wm size" | grep -i 'physical' | grep -oE '[0-9]+x[0-9]+' | head -1)

    if [ -z "$SIZE" ]; then
        SIZE=$(rsu "wm size" | grep -oE '[0-9]+x[0-9]+' | head -1)
    fi

    if [ -n "$SIZE" ]; then
        W=${SIZE%x*}
        H=${SIZE#*x}

        SMALL=$(( W < H ? W : H ))
        DPI=$(( SMALL * 160 / TARGET_SW ))

        rsu "wm density $DPI" >/dev/null

        NOW_SW=$(( SMALL * 160 / DPI ))

        DENSITY_MSG="Man hinh ${SIZE}, density = ${DPI} => smallest width ~ ${NOW_SW}dp"
    else
        DENSITY_MSG="Khong doc duoc kich thuoc man hinh."
    fi

    # KET QUA
    printf '\a'

    echo "=================================================="
    say "XONG!"

    echo "  Cai thanh cong: ${#OK_LIST[@]} clone ${OK_LIST[*]:+(so: ${OK_LIST[*]})}"

    if [ -n "$STOPPED_AT" ]; then
        warn "Dung tai $STOPPED_AT.apk vi khong tim thay file."
    fi

    if [ ${#FAIL_LIST[@]} -gt 0 ]; then
        warn "Loi: ${FAIL_LIST[*]}"
        echo "  Xem log: cat $LOG"
    fi

    echo "  $DENSITY_MSG"
    echo "  Khoi phuc density: su -c \"wm density reset\""

    echo "=================================================="
}

main "$@"
