# Debian 11 KVM/libvirt/Go 离线安装包制作与验证

在联网机器上制作 Debian 11 (bullseye) 的 KVM/libvirt 虚拟化栈及 Go 开发环境的离线安装包，并在目标机器上纯离线安装验证。

## 背景

- **制作端**：`10.12.5.216`（Debian 11, x86_64，可联网，使用阿里云镜像源）
- **验证端**：`10.12.5.217`（Debian 11, x86_64，纯离线安装）
- **认证**：`root / acoinfo`（两端一致）

## 离线包内容

| 类别 | 软件包/组件 | 版本 |
|------|-------------|------|
| 虚拟化 | qemu-kvm (qemu-system-x86) | 1:5.2+dfsg-11+deb11u3 |
| 虚拟化 | qemu-utils (qemu-img) | 1:5.2+dfsg-11+deb11u3 |
| 虚拟化 | libvirt-daemon / system / clients / dev | 7.0.0-3+deb11u3 |
| 网络 | bridge-utils (brctl) | 1.7-1 |
| 开发 | gcc | 4:10.2.1-1 |
| 开发 | git | 1:2.30.2-1+deb11u2 |
| 开发 | make | 4.3-4.1 |
| 开发 | Go | 1.24.5 (linux-amd64) |

离线包共 **350 个 .deb**（约 261 MB）+ Go 二进包（约 75 MB），打包后约 335 MB。

## 关键问题与解决

### Debian 11 bullseye 已 EOL 导致 security 源 404

`bullseye-security` / `bullseye-updates` 源的包索引记录了最新版本（如 `libvirt0 7.0.0-3+deb11u4`），但对应的 `.deb` 文件已从镜像下架（404），原因是 Debian 11 已结束标准支持进入 LTS，security 包归档。

**解决方案**：只使用 `bullseye main` 源，下载稳定发布版本（`+deb11u3` 系列），这些文件在镜像上完整保留。

```bash
# 禁用 security / updates 源
sed -i 's|^deb http://mirrors.aliyun.com/debian-security/|#deb ...|' /etc/apt/sources.list
sed -i 's|^deb http://mirrors.aliyun.com/debian/ bullseye-updates|#deb ...|' /etc/apt/sources.list
```

## 使用步骤

### 1. 制作离线包（在联网制作端执行）

```bash
bash make-offline-pkg.sh
```

产出：`/root/offline_pkg/offline-kvm-go-pkgs.tar.gz`

### 2. 传输到目标机器

```bash
scp offline-kvm-go-pkgs.tar.gz root@目标IP:/root/
```

> 若目标机器已配置 SSH 免密，可直接 scp；否则手动输入密码。

### 3. 离线安装（在目标机器执行）

```bash
bash install-offline.sh /root/offline-kvm-go-pkgs.tar.gz
```

### 4. 验证

```bash
bash verify-offline.sh
```

## 实际执行的离线安装命令（验证端 217）

```bash
# 1. 解压
cd /root && tar xzf offline-kvm-go-pkgs.tar.gz

# 2. 校验完整性
cd /root/debs && sha256sum -c ../SHA256SUMS  # 350 个 deb 全部 OK

# 3. 禁用网络源（保证纯离线）
cp /etc/apt/sources.list /root/sources.list.bak
sed -i 's|^deb http|#deb http|; s|^deb-src http|#deb-src http|' /etc/apt/sources.list
sed -i 's|^deb cdrom|#deb cdrom|' /etc/apt/sources.list

# 4. 离线安装所有 .deb（核心步骤）
cd /root/debs && dpkg -i ./*.deb

# 5. 安装 Go 1.24.5
cd /root && tar -C /usr/local -xzf go1.24.5.linux-amd64.tar.gz
cat >> /etc/profile.d/go.sh <<'EOF'
export PATH=$PATH:/usr/local/go/bin
export GOPATH=/root/go
export GOPROXY=https://proxy.golang.org,direct
EOF
chmod +x /etc/profile.d/go.sh
```

## 验证结果

| 组件 | 状态 | 版本 |
|------|------|------|
| qemu-system-x86_64 | ✅ | 5.2.0 |
| qemu-img | ✅ | 5.2.0（创建/查询镜像正常）|
| virsh / libvirtd | ✅ | 7.0.0（服务运行中）|
| bridge-utils | ✅ | 1.7-1 |
| libvirt-dev | ✅ | 头文件存在 |
| gcc | ✅ | 10.2.1 |
| git | ✅ | 2.30.2 |
| make | ✅ | 4.3 |
| Go | ✅ | go1.24.5 |

## 备注

- `g++` 未包含（需求清单为 `gcc`）；如需 C++ 编译，追加 `g++` 到 `make-offline-pkg.sh` 的 `PKGS` 数组即可。
- `/dev/kvm` 不存在是宿主机未开启嵌套虚拟化的环境限制，与离线包无关。
- Go 环境变量写入 `/etc/profile.d/go.sh`，新登录 shell 自动生效（`bash -lc 'go version'` 可验证）。
