# wpi-update
本脚本用于从walnutpi官方apt服务器获取更新,安装各种包

# 使用
## 执行更新
检测更新，如果有更新的话会输出log，输入y按回车即可当场更新
```
sudo wpi-update
```
检测更新，有更新就自动安装，跳过输入y的步骤
```
sudo wpi-update -y
```

## 输出新版本的版本号
```
sudo wpi-update -v
```