#!/bin/bash
#
# write_img2sd.sh

if [ $(uname) != "Darwin" ]; then
    echo "このスクリプトは MacOS 専用です。処理を終了します。"
    exit 1
fi

# 終了時に一時ファイルを消すための仕込み
trap do_exit 0 1 2 3 13 15

########################################
# 主処理部
do_main() {
    targetfile=$1

    # 書き込み対象のファイルが存在することを確認する
    file_existcheck "$targetfile"

    # 作業開始時点（SDカード装着前）のドライブ一覧を取得する
    get_drivelist_prev

    echo -n "SDカードを装着して enter を押してください"
    read

    # SDカード装着後のドライブ一覧を取得する
    get_drivelist_post

    # SDカードのドライブを検出する
    detect_SD_device

    # SDカードのデバイス名を取得する
    sd_device=$( get_SD_devicename )
    echo "SDデバイス名を検出しました: $sd_device"
    echo ""

    # SD カードへのディスクイメージ書き込みを行う
    write_image $targetfile $sd_device

    # デバイスを取り外し可能な状態にする
    detach_device $sd_device

}

########################################
# ファイルの有無をチェックする
file_existcheck() {
    if [ ! -e $1 ]; then
        echo "ファイル $1 が見つかりません。処理を終了します。"
        exit 1
    fi
}

########################################
# 作業開始前のドライブ一覧を取得する
get_drivelist_prev() {
    file_diskutil_info_prev=$( mktemp )
    diskutil list | awk '$1 ~ /^\// { print $1 }' > $file_diskutil_info_prev
}

########################################
# 作業開始中のドライブ一覧を取得する
get_drivelist_post() {
    file_diskutil_info_post=$( mktemp )
    diskutil list | awk '$1 ~ /^\// { print $1 }' > $file_diskutil_info_post
}

detect_SD_device() {
    diff $file_diskutil_info_prev $file_diskutil_info_post > /dev/null
    if [ $? -eq 0 ]; then
        echo "SDカードを認識できません。カードを所定の手順で抜いた後、最初からやり直してください。"
        exit 1
    fi
}
get_SD_devicename() {

    sort $file_diskutil_info_prev $file_diskutil_info_post | uniq -u
    rm $file_diskutil_info_prev $file_diskutil_info_post
}

write_image() {
    which pv > /dev/null
    if [ $? -eq 0 ]; then
        pvcat="pv"
    else
        pvcat="cat"
    fi

    rdevice=$( echo $2 | sed s#/dev/disk#/dev/rdisk#g )

    echo "SDカードへの書き込み準備を行います。プロンプトが表示された場合はログインパスワードを入力してください。"
    #echo "sudo diskutil umountdisk $rdevice"
    sudo diskutil umountdisk $rdevice

    #echo "$pvcat $1 | sudo dd of=$rdevice bs=1m"
    $pvcat $1 | sudo dd of=$rdevice bs=1m
    echo "書き込み完了しました"
    echo ""
}

detach_device() {
    diskutil eject $1
    echo "SDカードデバイス $1 を取り外してください。"
}

do_exit() {
    for file in $file_diskutil_info_prev $file_diskutil_info_post ; do
        if [ -e $file ]; then
            rm $file
        fi
    done
}

do_main "$@"
