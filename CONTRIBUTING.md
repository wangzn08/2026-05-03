# 贡献指南

感谢您对本项目的关注！本文档将帮助您参与项目开发。

## 开发环境

### 环境配置

```bash
# 一键配置开发环境
bash install.sh

# 或手动配置
source setup_env.sh
```

### 目录结构

```
2026-05-03/
├── docs/               # 项目文档
├── hw/                 # 硬件设计 (RTL)
│   └── rtl/           # Verilog 源代码
├── firmware/           # 固件代码 (C + 汇编)
├── sim/                # 仿真文件
├── tests/              # 测试用例
├── scripts/            # 辅助脚本
├── training/           # 模型训练代码
├── dataset/            # MNIST 数据集
├── tools/              # 工具脚本
├── Makefile            # 构建配置
├── run.sh              # 运行脚本
└── install.sh          # 安装脚本
```

## 贡献流程

### 1. Fork 项目

在 GitHub 上 Fork 本仓库。

### 2. 克隆到本地

```bash
git clone https://github.com/YOUR_USERNAME/2026-05-03.git
cd 2026-05-03
```

### 3. 创建特性分支

```bash
git checkout -b feature/your-feature-name
```

分支命名规范：
- `feature/*` - 新功能
- `bugfix/*` - 修复 bug
- `docs/*` - 文档更新
- `refactor/*` - 代码重构

### 4. 提交更改

```bash
git add .
git commit -m "feat: 添加新功能描述"
git push origin feature/your-feature-name
```

提交信息规范：
- `feat:` - 新功能
- `fix:` - 修复 bug
- `docs:` - 文档更新
- `style:` - 代码格式调整
- `refactor:` - 重构
- `test:` - 测试相关
- `chore:` - 构建/工具相关

### 5. 创建 Pull Request

在 GitHub 上创建 Pull Request，描述您的更改。

## 代码规范

### Verilog

- 使用 4 空格缩进
- 模块名使用小写字母和下划线
- 信号名使用小写字母和下划线
- 添加必要的注释

### C 代码

- 使用 4 空格缩进
- 函数名使用小写字母和下划线
- 常量使用大写字母和下划线
- 添加必要的注释

### Python

- 遵循 PEP 8 规范
- 使用 4 空格缩进
- 添加必要的文档字符串

## 测试

### 运行仿真

```bash
# 纯仿真
./run.sh -n

# 带波形仿真
./run.sh -s

# 完整流程
./run.sh
```

### 添加测试用例

1. 在 `tests/` 目录下创建新的测试文件
2. 遵循现有的测试格式
3. 确保测试通过

## 问题反馈

如有问题或建议，请在 GitHub 上创建 Issue。

## 许可证

贡献即表示您同意您的代码在 MIT 许可证下发布。
