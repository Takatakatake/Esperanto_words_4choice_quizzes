#!/bin/bash

###############################################################################
# git_helper.sh (Revised Perfect Edition)
#
# 改良点:
#   - evalの廃止によるセキュリティとファイル名処理の安全性向上
#   - 現在のブランチを自動検知してPull/Rebaseを実行
#   - 失敗時の安全なStash処理フロー
#   - 視認性の高いメニューと即時リターン
###############################################################################

# --- 設定セクション ---

# カラー設定
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ログファイルの保存先
LOG_FILE="$HOME/git_helper.log"

# --- 共通関数セクション ---

# ログ記録
log_action() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp - $1" >> "$LOG_FILE"
}

# コマンド実行ラッパー (eval不使用・配列引数対応)
# 使用法: run_command git commit -m "message"
run_command() {
    echo -e "${BLUE}Running: $*${NC}"
    
    # 配列としてコマンドを実行 (特殊文字も安全に扱われます)
    "$@"
    local status=$?

    if [ $status -eq 0 ]; then
        echo -e "${GREEN}Success${NC}"
        log_action "SUCCESS: $*"
        return 0
    else
        echo -e "${RED}Failed (Exit Code: $status)${NC}"
        log_action "FAILED: $* (Exit Code: $status)"
        return $status
    fi
}

# 現在のブランチ名を取得する関数
get_current_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || echo "HEAD"
}

# ヘッダ表示
show_header() {
    echo ""
    echo -e "${YELLOW}========================================"
    echo "       Git Helper Script (Safe Mode)"
    echo -e "========================================${NC}"
    echo -e "Current Branch: ${GREEN}$(get_current_branch)${NC}"
    echo ""
}

# メニュー表示
show_menu() {
    echo "1.  git status"
    echo "2.  git add (指定パス)"
    echo "3.  git commit"
    echo "4.  git push"
    echo "5.  git pull (通常 or --rebase)"
    echo "6.  git log"
    echo "7.  git branch"
    echo "8.  git checkout (ブランチ切替)"
    echo "9.  git merge (ブランチ統合)"
    echo "10. git stash"
    echo "11. git remote -v"
    echo "12. git diff"
    echo "13. [Safety] git stash -> pull --rebase -> pop"
    echo "h.  Help"
    echo "0.  Exit"
    echo "----------------------------------------"
}

# ヘルプ表示
show_help() {
    clear
    echo -e "${GREEN}Git Helper Script - Help${NC}"
    echo "---------------------------------"
    echo "Option 13 の挙動について:"
    echo "  1. 作業中の変更を stash に退避"
    echo "  2. 現在のブランチに対してリモートから pull --rebase"
    echo "  3. pull が成功した場合のみ、stash pop を実行"
    echo "  ※ pull でコンフリクトした場合は stash pop を中断します。"
    echo "---------------------------------"
}

# --- 個別コマンド処理 ---

# 2. git add
git_add_path() {
    echo -n "Enter path to add (default: '.'): "
    read -r add_path
    if [ -z "$add_path" ]; then
        add_path="."
    fi
    run_command git add "$add_path"
}

# 3. git commit
git_commit() {
    echo "Choose commit mode:"
    echo "0) Default: \"Update <Timestamp>\""
    echo "1) Single-line message"
    echo "2) Editor (Multi-line)"
    read -p "Select mode [0-2] (default: 0): " commit_choice
    commit_choice=${commit_choice:-0}

    case $commit_choice in
        0)
            local default_msg="Update $(date '+%Y-%m-%d %H:%M')"
            echo -e "${BLUE}Message: \"$default_msg\"${NC}"
            run_command git commit -m "$default_msg"
            ;;
        1)
            read -p "Enter message: " msg
            if [ -z "$msg" ]; then
                msg="Update $(date '+%Y-%m-%d %H:%M')"
            fi
            run_command git commit -m "$msg"
            ;;
        2)
            echo -e "${BLUE}Opening editor...${NC}"
            run_command git commit
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            ;;
    esac
}

# 5. git pull (Safe Dynamic Branch)
git_pull_menu() {
    local current_branch
    current_branch=$(get_current_branch)
    
    echo "Pulling for branch: $current_branch"
    echo "  0) Normal pull (default)"
    echo "  1) Pull with --rebase"
    read -p "Select mode [0/1] (default: 0): " choice
    choice=${choice:-0}

    case $choice in
        0) run_command git pull origin "$current_branch" ;;
        1) run_command git pull --rebase origin "$current_branch" ;;
        *) echo -e "${RED}Invalid choice.${NC}" ;;
    esac
}

# 13. Smart Stash Pull Rebase
git_smart_sync() {
    local current_branch
    current_branch=$(get_current_branch)

    echo -e "${YELLOW}Target Branch: $current_branch${NC}"
    echo "Step 1: Stashing local changes..."
    run_command git stash
    
    echo "Step 2: Pulling with rebase..."
    # run_commandは成功時0を返す
    if run_command git pull --rebase origin "$current_branch"; then
        echo "Step 3: Popping stash..."
        run_command git stash pop
    else
        echo -e "${RED}!!! Pull Failed. Stash pop skipped to prevent data loss. !!!${NC}"
        echo "Fix the conflicts, then run 'git stash pop' manually."
        log_action "FAILED: Smart Sync interrupted at pull stage."
    fi
}

# --- メインループ ---

while true; do
    show_header
    show_menu
    read -p "Choose option: " choice
    echo "" # 改行

    case $choice in
        1)  run_command git status ;;
        2)  git_add_path ;;
        3)  git_commit ;;
        4)  
            curr=$(get_current_branch)
            run_command git push origin "$curr" 
            ;;
        5)  git_pull_menu ;;
        6)  run_command git log --oneline --graph --decorate -n 15 ;; # 見やすいログオプション
        7)  run_command git branch -a ;;
        8)
            read -p "Enter branch name to checkout: " br
            [ -n "$br" ] && run_command git checkout "$br"
            ;;
        9)
            read -p "Enter branch name to merge: " br
            [ -n "$br" ] && run_command git merge "$br"
            ;;
        10) run_command git stash ;;
        11) run_command git remote -v ;;
        12) run_command git diff ;;
        13) git_smart_sync ;;
        h|H) show_help ;;
        0)
            echo -e "${GREEN}Exiting...${NC}"
            break
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            ;;
    esac
done
