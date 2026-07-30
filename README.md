# wpi-update

WalnutPi 开发板的系统更新工具，从官方 apt 服务器获取更新并安装各类软件包。

## 安装

```bash
sudo bash install
```

执行后 `wpi-update` 命令会被安装到 `/usr/bin/wpi-update`，之后可直接使用。

## 命令参考

### 系统更新

```bash
sudo wpi-update
```

检查是否有新版本可用。如果有更新，会展示更新日志，确认后自动执行。

```bash
sudo wpi-update -y
```

跳过确认步骤，直接执行更新。

```bash
sudo wpi-update -N
```

强制重新安装当前版本（即使本地已是最新）。可配合 `-y` 使用：`sudo wpi-update -Ny`。

### 安装指定软件包

```bash
sudo wpi-update install <包名>
```

从 WalnutPi 官方 apt 源安装指定的软件包。

### 查看信息

```bash
wpi-update -v      # 查看本地 wpi-update 脚本版本
wpi-update -s      # 查看服务器端最新系统版本号
wpi-update -l      # 查看自上次更新以来的发布日志
```

## 更新内容说明

执行系统更新时，脚本会自动完成以下步骤：

1. **移除废弃包** — 删除新版系统中不再需要的旧软件包
2. **安装新增包** — 安装新版系统引入的新软件包
3. **升级已有包** — 将所有已安装的包升级到最新版本
4. **写回版本号** — 更新 `/etc/WalnutPi-release` 中的版本信息

更新完成后**重启设备**使所有改动生效。

## 注意事项

- 必须以 **root 权限** 运行（使用 `sudo`）
- 更新前请**备份个人数据**，以防意外
- 需要**网络连接**，脚本会访问 `apt.walnutpi.com`

## 开发者说明

因为单个文件太长不好开发，所以开发时是先在src目录下一段段开发，修改完成后运行 `bash build.sh`， 即将src目录下的脚本合并生成 `wpi-update`。
