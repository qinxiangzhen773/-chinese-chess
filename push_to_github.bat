@echo off
chcp 65001 >nul
echo ============================================
echo   中国象棋 Git 初始化 + 推送脚本
echo ============================================
echo.

cd /d "%~dp0"

echo [1/4] 初始化 Git 仓库...
git init

echo [2/4] 添加所有文件...
git add -A

echo [3/4] 提交代码...
git commit -m "Initial commit: Chinese Chess with NNUE engine"

echo [4/4] 等待你创建 GitHub 仓库...
echo.
echo ============================================
echo   接下来在浏览器中操作：
echo.
echo   1. 打开 https://github.com/new
echo   2. Repository name: chinese-chess (或任意名字)
echo   3. 不要勾选 "Add a README file"
echo   4. 不要勾选 ".gitignore"
echo   5. 点击 "Create repository"
echo   6. 复制弹出的三行命令（以 git remote add 开头）
echo     粘贴到本窗口中运行
echo.
echo   或手动执行（替换 YOUR_USERNAME）：
echo   git remote add origin https://github.com/YOUR_USERNAME/chinese-chess.git
echo   git branch -M main
echo   git push -u origin main
echo.
echo   推送后，GitHub 自动开始云端打包！
echo   完成后在 Actions 页面下载 APK。
echo ============================================
pause
