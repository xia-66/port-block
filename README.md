# port-block

Debian/Ubuntu 服务器 nftables 端口屏蔽脚本。默认屏蔽 `cn` IP 访问本机 `55555` 端口，默认协议为 `tcp + udp`。

## 在线一键脚本

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/xia-66/port-block/master/port-block.sh)"
```

运行后进入交互菜单，可选择：

- 查看当前已配置的屏蔽规则
- 新增端口屏蔽，并启用 IP 库每周自动更新
- 修改已有端口屏蔽
- 卸载规则、更新脚本和自动更新定时器

安装完成后会创建 systemd timer，自动更新 IP 库并重新加载 nftables 规则。
