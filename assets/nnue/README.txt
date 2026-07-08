NNUE 神经网络权重文件
========================

此目录用于存放 Pikafish 引擎的 NNUE 权重文件。

使用方法：
----------
1. 从以下地址下载 pikafish.nnue 文件：
   https://github.com/official-pikafish/Networks/releases

2. 将下载的 pikafish.nnue（或 pikafish.zip 解压后的 .nnue 文件）
   放入此目录，命名为 pikafish.nnue

3. 重新编译 APK，权重将自动打包到 APK 中

注意：
-----
- 如果未放入权重文件，App 会在首次启动时尝试从网络自动下载
- 若下载也失败，AI 将以传统手写评估运行（棋力约降低 200-300 Elo）
- NNUE 文件大小约 20-40 MB，会使 APK 体积增大相应大小
