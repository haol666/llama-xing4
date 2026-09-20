
# llama.cpp Xing4.0 Docker 镜像

> PR #29012: Add Support for Xing4.0（TeleAI 星辰 Xing4.0-29B-A4B，DeepSeek-V3 MLA + MoE + mHC + MTP）  
> 源分支: `shuxiaoqiong/llama.cpp:xing4_0-port`（PR head，构建始终拉取分支最新 commit）  
> 镜像通过 GitHub Actions 自动构建并发布到 GHCR  
> **PR #29012 尚未合入 llama.cpp master，本镜像为非官方预览构建**

## 镜像列表

GitHub Actions 构建完成后，以下镜像可用：

| 镜像 | 标签 | 说明 | 镜像大小 |
|------|------|------|---------|
| `ghcr.io/haol666/llama-xing4:cuda` | 多架构 CUDA | 覆盖 75/80/86/89/90 | ~3.5 GB |
| `ghcr.io/haol666/llama-xing4:cuda-75` | Turing 专用 | 2080Ti / T4 精简编译 | ~2.5 GB |
| `ghcr.io/haol666/llama-xing4:cpu` | 纯 CPU | 无 GPU 依赖（29B MoE 很慢，仅冒烟测试） | ~450 MB |

## 关于 Xing4.0-29B-A4B

- 中国电信（TeleAI / 中电信人工智能科技）2026-09-17 发布的轻量级代码智能体大模型
- MoE 架构：总参数 29B，激活参数 4B；原生 256K 上下文（可扩展 512K+）
- 骨干为 DeepSeek-V3 风格：MLA 多头潜变量注意力 + DeepSeekMoE + MTP 多 Token 预测头
- 自研 mHC（流形约束超连接，4-stream + Sinkhorn 归一化）替换标准残差连接
- GGUF 内 `general.architecture = "xing4_0"`，**官方 llama.cpp 无法加载**，必须使用本 PR 分支构建的二进制
- GGUF 必须用 PR 分支的转换脚本生成（HF safetensors → GGUF），社区量化版（如 IQ4_NL 19GiB）适配 22GB 显存

## 快速开始

### 1. 拉取镜像

```bash
# GPU 版（多架构）
docker pull ghcr.io/haol666/llama-xing4:cuda

# GPU 版（2080Ti 专用，镜像更小）
docker pull ghcr.io/haol666/llama-xing4:cuda-75

# CPU 版
docker pull ghcr.io/haol666/llama-xing4:cpu
```

### 2. 准备模型

```bash
mkdir -p models && cd models

# 原始权重（HuggingFace，需要自行用 PR 分支转换脚本转 GGUF）
# https://huggingface.co/XingChen-AGI/Xing4.0-29B-A4B
# https://modelscope.cn/models/XingChen-AGI/Xing4.0-29B-A4B

# 或直接下载社区已转换的 GGUF（确认 architecture=xing4_0）
cd ..
```

### 3. 运行

**Docker Compose（推荐）:**

```bash
cp .env.example .env
# 确认 TARGET_MODEL 与 models/ 目录下的 GGUF 文件名一致

docker compose up -d xing4-gpu
```

**Docker CLI:**

```bash
docker run -d --gpus all -p 8080:8080 \
  -v $(pwd)/models:/models:ro \
  --shm-size 4g \
  ghcr.io/haol666/llama-xing4:cuda \
  -m /models/Xing4.0-29B-A4B-1Q3M.gguf \
  -c 32768 -ngl 99 \
  -fa on -ctk q8_0 -ctv q8_0 \
  --host 0.0.0.0 --port 8080
```

**MTP 投机解码（PR 已实现 Xing4.0 的 MTP head 推理图）:**

```bash
docker run -d --gpus all -p 8080:8080 \
  -v $(pwd)/models:/models:ro \
  --shm-size 4g \
  ghcr.io/haol666/llama-xing4:cuda \
  -m /models/Xing4.0-29B-A4B-1Q3M.gguf \
  --spec-type draft-mtp --spec-draft-n-max 4 \
  -c 32768 -ngl 99 -fa on \
  --host 0.0.0.0 --port 8080
```

### 4. 测试

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "xing4.0-29b-a4b",
    "messages": [{"role": "user", "content": "你好"}],
    "max_tokens": 100
  }'
```

## 显存参考（PR 作者实测）

| 量化 | 体积 | 显存需求 | 2080Ti 22G |
|------|------|---------|-----------|
| F16 | 59 GiB | 60GB+ | 不适用 |
| IQ4_NL | 19 GiB | ~20GB | 可全 GPU（-ngl 99） |

> 4B 激活参数使解码吞吐可观（PR 作者环境 tg128 ~151 t/s）；22GB 显存建议 IQ4_NL/相似体积量化。

## GitHub Actions 自动构建

### 工作流程

文件: `.github/workflows/build-xing4.yml`

```
push 到 main ──┬──> build-cuda (75;80;86;89;90) ──> ghcr.io/...:cuda
               ├──> build-cuda (75)             ──> ghcr.io/...:cuda-75
               └──> build-cpu                   ──> ghcr.io/...:cpu

手动触发 (workflow_dispatch)
  ├── 可选 CUDA_ARCH
  └── 可选是否推送

每周一 UTC 02:00 自动重建
  （git clone 拉取 xing4_0-port 分支 HEAD，自动跟进 PR 更新）
```

### 镜像标签策略

```
ghcr.io/haol666/llama-xing4:cuda          ← 最新
ghcr.io/haol666/llama-xing4:cuda-20260920  ← 日期快照
ghcr.io/haol666/llama-xing4:cuda-63c16fb   ← 源 commit 前缀
```

## Unraid 部署

### 前提条件

1. 安装 **NVIDIA Driver** 插件 (Community Applications)
2. 安装 **NVIDIA Container Toolkit** 插件
3. Docker vdisk 大小改为 **50GB+** (Settings → Docker)

### 部署步骤

```bash
mkdir -p /mnt/cache/appdata/llama-xing4/models
cd /mnt/cache/appdata/llama-xing4

wget https://raw.githubusercontent.com/haol666/llama-xing4/main/docker-compose.yml
wget https://raw.githubusercontent.com/haol666/llama-xing4/main/.env.example
cp .env.example .env

# 编辑 .env 确认模型名；GGUF 放入 models/ 目录
# 2080Ti 建议把 xing4-gpu 的镜像标签改为 :cuda-75

docker compose up -d xing4-gpu
docker compose logs -f xing4-gpu
```

### Unraid 注意事项

- **vdisk 大小**: 默认 20GB 不够（镜像层 + 解压），改 50GB+
- **CUDA 架构**: 2080Ti 用 `:cuda-75` 标签，避免多架构大镜像
- **网络**: 国内拉取 ghcr.io 慢，提前 `docker pull` 或用已有 tar 导入
- **共享内存**: compose 已设 `shm_size: 4g`，CLI 方式需手动加 `--shm-size 4g`

## 对比测试

docker-compose.yml 内置对比服务:

```bash
docker compose up -d xing4-gpu mtp-gpu baseline-gpu

curl http://localhost:8080/v1/chat/completions  # 普通推理
curl http://localhost:8081/v1/chat/completions  # MTP 投机解码
curl http://localhost:8082/v1/chat/completions  # 基线
```

## 关键参数

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| `-ngl 99` | 全部层放 GPU | 22G 显存 + IQ4_NL 可行 |
| `-fa on` | Flash Attention | 推荐开启 |
| `-ctk q8_0 -ctv q8_0` | KV cache 量化 | 推荐开启 |
| `--spec-type draft-mtp` | 内置 MTP 投机解码 | 需 GGUF 含 MTP head 张量 |
| `--spec-draft-n-max 4` | MTP 草稿深度 | 4 |
| `-c` | 上下文 | 按显存余量，模型支持 256K |
| `--cpu-moe` / `--n-cpu-moe N` | 专家层放 CPU | 显存不足时兜底 |

## 已知问题与风险

| 问题 | 说明 / 应对 |
|------|------------|
| PR #29012 未合并 | CI bot 建议拆分（CPU/CUDA 分开）；本镜像跟踪分支 HEAD 自动跟进 |
| 分支 force-push | PR 更新后重建镜像即可；若张量名/参数变动，**旧 GGUF 需用新分支重转** |
| mergeable_state=unstable | PR 的 CI 有红项，若本仓库构建失败请先看 Actions 日志 |
| 官方镜像不兼容 | 用官方 llama.cpp 加载会报 `unknown model architecture: 'xing4_0'`，必须用本镜像 |
| CPU 推理无实用价值 | 29B MoE 纯 CPU 极慢（PR 作者原话），cpu 镜像仅冒烟测试 |
| 架构合并后本仓库退役 | PR 合入 master 后官方镜像即可用，本仓库停止每周构建 |

## 文件结构

```
llama-xing4/
├── .github/workflows/
│   └── build-xing4.yml       # GitHub Actions CI/CD
├── .env.example              # 环境变量模板
├── Dockerfile.cuda           # CUDA GPU 构建
├── Dockerfile.cpu            # CPU-only 构建
├── docker-compose.yml        # 编排文件 (GPU+CPU+MTP+基线)
├── build.sh                  # 本地构建/运行脚本
└── README.md                 # 本文档
```
