# KDE-BOOTC
The motivation for this project is inspired from the increasing popularity of atomic distros as technology advances. The Fedora project is one of the leaders in bringing this concept to the public, with other projects following suit. This approach offers significant benefits in terms of stability and security.

They apply updates as a single transaction, known as atomic upgrades, which means if an update doesn't work as expected, the system can instantly roll back to its last stable state, saving users from potential issues. The immutable nature of the system components reduces the risk of system corruption and unauthorised modifications as the core system files are read-only, making them impossible to modify.

If you are planning to spin off various instances from the same image (e.g. setting up computers for members of your family or work), atomic distros provide a reliable desktop experience where every instance of the desktop is consistent with others, reducing discrepancies in software versions and behaviour.

Mainstream sources like Fedora and Universal Blue offer various atomic desktops with curated configurations and package selections for the average user. But what if you're ready to take control of your desktop and customise it entirely, from packages and configurations to firewall, DNS, and update schedules?

Thanks to bootc and the associated tools, building a personalised desktop experience is no longer difficult. This project aims to provide you with basic tips to help you customise your desktop. This is not a final product, but the means and steps to build your own.

## What is bootc?
Using existing container building techniques, bootc allows you to build your own OS. Container images adhere to the OCI specification and utilise container tools for building and transporting your containers. Once installed on a node, the container functions as a regular OS.

The container image includes a Linux kernel (e.g., in `/usr/lib/modules`) for booting. Bootc includes a package manager, allowing you to scrutinise installed and available packages from existing and added repositories. Additionally, using `bootc usr-overlay`, bootc mounts an overlay on `/usr`, enabling temporary package installation via dnf. After testing, this overlay can be dropped at boot or manually unmounted (`mount -l /usr`). It is advisable to remove all packages installed this way before unmounting `/usr` to ensure any configuration files in `/etc` are also removed.

The filesystem structure follows ostree specifications:

- The `/usr` directory is read-only, with all changes managed by the container image.
- The `/etc` directory is editable, but any changes applied in the container will be transferred to the node unless the file was modified locally.
- Additions to `/var` (including `/var/home`) are made during the first boot. Afterwards, `/var` remains untouched.

The full documentation for bootc can be found here: https://bootc-dev.github.io/bootc/

## What is kde-bootc?
This project utilises `quay.io/fedora/fedora-bootc` as the base image to create a customizable container for building your personalised Fedora KDE immutable desktop. 

The aim is to explain basic concepts and share some useful tips. It is important to note that this template is meant to be modified according to your needs, so it is not necessarily a final product. However, it will work out of the box.

Although it is tailored to KDE Plasma, most of the concepts and methodologies also apply to other desktop environments.

## Repository structure
I tried to organise the repository for easy reading and maintenance. Files are stored in functional and well-defined directories, making them easy to find and understand their purpose and where they will be placed in the container image. 

Each file follows a specific naming convention. For instance a file `/usr/lib/credstore/home.create.admin` is named as `usr__lib__credstore__home.create.admin`

**Folders:**
- *.github*: Contains an example of GitHub action to build the container and publish the image
- *scripts*: Contains scripts to be ran from the Containerfile during building
- *system*: Files to be copied to `/usr` and `/etc`
- *systemd*: Systemd unit files to be copied to `/usr/lib/systemd`

## Explaining the Containerfile step by step
### Setup filesystem
If you plan to install software on day 2, after the *kde-bootc* installation is complete, you may need to link `/opt` to `/var/opt`. Otherwise, `/opt` will remain an immutable directory that can only be populated from the container build.
```
RUN rmdir /opt && ln -s -T /var/opt /opt
```
In some cases, for successful package installation the `/var/roothome` directory must exist. If this folder is missing, the container build may fail. It is advisable to create this directory before installing the packages.
```
RUN mkdir /var/roothome
```
### Prepare packages
To simplify the installation of packages, I found useful keeping them as a resource under `/usr/share`. 
- All additional packages to be installed on top of *fedora-bootc* and the *KDE environment* are documented in `packages-added`. 
- Packages to be removed from *fedora-bootc* and the *KDE environment* are documented in `packages-removed`. 
- For convenience, the packages included in the base *fedora-bootc* are documented in `packages-fedora-bootc`.
```
COPY --chmod=0644 ./system/usr__local__share__kde-bootc__packages-removed /usr/local/share/kde-bootc/packages-removed
COPY --chmod=0644 ./system/usr__local__share__kde-bootc__packages-added /usr/local/share/kde-bootc/packages-added
RUN jq -r .packages[] /usr/share/rpm-ostree/treefile.json > /usr/local/share/kde-bootc/packages-fedora-bootc
```
### Install repositories
This section handles installing additional repositories needed before installing packages. 

In this example, I'm including Tailscale, which is commonly used by the community, but the same principle applies to any other source you may add to your repositories. 

Adding repositories uses the `config-manager` verb, available as a DNF5 plugin. This plugin is not pre-installed by default in *fedora-bootc*, so it will need to be installed beforehand.
```
RUN dnf -y install dnf5-plugins
RUN dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
```
### Install packages
For clarity and task separation, I divided the installation into two steps:
Installation of environment and groups:
```
RUN dnf -y install @kde-desktop-environment
```
And the installation of all other individual packages:
```
RUN grep -vE '^#' /usr/local/share/kde-bootc/packages-added | xargs dnf -y install –allowerasing
```
The script will select all lines not starting with `#` to be passed as arguments to `dnf -y install`. The `--allowerasing` option is necessary for cases like installing `vim-default-editor`, which would conflict with `nano-default-editor`, removing the latter first. 

This is one of the key files to modify to customise your installation.
### Remove packages
Some of the standard packages included in `@kde-desktop-environment` don’t behave well and sometimes conflict with an immutable desktop, so they need to be removed. 

This is also an opportunity to remove software you will never use, saving resources and storage.
```
RUN grep -vE '^#' /usr/local/share/kde-bootc/packages-removed | xargs dnf -y remove
RUN dnf -y autoremove
RUN dnf clean all
```
The criteria used in this project is summarise below:
- Remove packages that conflict with bootc and its immutable nature.
- Remove packages that provide no benefit and bring unwanted dependencies, such as DNF4 and GTK3.
- Remove packages that handle deprecated services like IPTables.
- Remove unnecessary packages that are resource-heavy, or bring unnecessary services.
### Configuration
This section is designated for copying all necessary configuration files to `/usr` and `/etc`. As recommended by the *bootc project*, prioritise using `/usr` and use `/etc` as a fallback if needed.

Bash scripts that will be used by systemd services are stored in `/usr/local/bin`:
```
COPY --chmod=0755 ./system/usr__local__bin/* /usr/local/bin/
```
Custom configuration for new users' home directories will be added to `/etc/skel/`. This project adds `.bashrc.d/kde-bootc` to customise bash, and it can be tweaked as needed.
```
COPY --chmod=0644 ./system/etc__skel__kde-bootc /etc/skel/.bashrc.d/kde-bootc
```
If you're building your container image on GitHub and keeping it private, you'll need to create a **GITHUB_TOKEN** to download the image. Further information on [GitHub container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

The **GITHUB_TOKEN** can be created from global settings (not the repository settings) under *Developer settings*. The only required scope for the token is `read:packages`, which will allow you to download your image.

Using this token, create the **GITHUB_CREDENTIAL** by generating a base64 output from your **GitHub USERNAME** and **GITHUB_TOKEN** combination: 
```
echo <GitHub USERNAME>:<GITHUB_TOKEN> | base64
```
The output is then added to the `usr__lib__ostree__auth.json` file, which is copied to `/usr/lib/ostree/auth.json` for bootc to reference when downloading the image from the GitHub registry to update the system.
```
COPY --chmod=0600 ./system/usr__lib__ostree__auth.json /usr/lib/ostree/auth.json
```
### Users
This section is divided into two groups: one copies configuration files, and the other runs scripts to set up the system. 

I opted for `systemd-homed` users because they are better suited than regular users for immutable desktops, preventing potential drift if `/etc/passwd` is modified locally. Additionally, each user home benefits from LUKS encrypted volume.

The process begins when `firstboot-setup` runs, triggered by `firstboot-setup.service` during boot. It executes `homectl firstboot`, which checks if any regular home areas exist. If none are found, it searches for service credentials starting with `home.create.` to create users at boot. 

Service credentials are imported into the systemd service using the following parameter:
```
firstboot-setup.service
  ...
  ImportCredential=home.create.*
```
For more details, refer to `homectl` and `systemd.exec` manual pages.

The homed identity file (`usr__lib__credstore__home.create.admin`) sets the user's parameters, including username, real name, storage type, etc. This file can be modified to customise your user(s). 

This example sets up a homed area using LUKS storage and a BTRF filesystem. I noticed that for LUKS storage, at least two parameters must be defined: `diskSize` and `rebalanceWeight`. If either is missing, `systemd-homed` will add a `perMachine` section defining these parameters, which will take precedence over the top-level user record (you may have set) because `perMachine` section supersedes them.

**Most common parameters to adjust:**
- `userName`: A single word for your username and home directory. In this example, it is `admin`. 
- `realName`: Full Name
- `diskSize`: The size of the LUKS storage volume, calculated in bytes. For instance, 1 GB equals 1024x1024x1024 bytes, which is 1073741824 bytes. This example sets up a 10GB storage volume. 
- `rebalanceWeight`: Relevant only when multiple user accounts share the available storage. If `diskSize` is defined, this parameter can be set to `false`. 
- `uid/gid`: User and Group ID. The default range for regular users is 1000-6000, and for `systemd-homed` users, it is 60001-60513. However, you can assign uid/gid for `systemd-homed` users from both ranges; in this example, they are set to `1000`.
- `memberOf`: The groups the user belongs to. As a power user, it should be part of the `wheel` group. 
- `hashedPassword`: This is the hashed version of the password stored under secret. Setting up an initial password allows `homectl firstboot` to create the user without prompting. This password should be changed afterwards (`homectl passwd admin`). The hash password can be created using the `mkpasswd` utility. 

The identity file is stored in one of the directories where `systemd-homed` expects to find credentials.
```
COPY --chmod=0644 ./system/usr__lib__credstore__home.create.admin /usr/lib/credstore/home.create.admin
```
For more information on user records, visit: https://systemd.io/USER_RECORD/

Another key parameter to set up is the range for `/etc/subuid` and `/etc/subgid` for the `admin` user. This range is necessary for running rootless containers, as each uid inside the container will be mapped to a uid outside the container within this range. When using `systemd-homed`, note that the available uid/gid ranges are predefined by systemd, and some ranges may be unavailable. Therefore, the chosen range in these files must adhere to these limitations.

When running `findmnt` or `mount` command, the option `idmapped` will show for `/var/home/admin` mount point, indicating that only the available ranges are being used. 

The available range is 524288…1879048191. In this example, I chose 1000001 to easily identify the service running in the container. For instance, if the container is running Apache with id=48, the volume or folder bound to it will have id=1000048.

For more information on available ranges, visit: https://systemd.io/UIDS-GIDS/

The `config-users` script sets this up and also creates a temporary password for the root user. As I will explain later, having a root user as an alternative login is important.

The next script will set up `authselect` to enable authenticating the `admin` user on the login page. To achieve this, we need to enable the features `with-systemd-homed` and `with-fingerprint` (if your computer has a fingerprint reader) for the local profile.
```
COPY --chmod=0755 ./scripts/* /tmp/scripts/
RUN /tmp/scripts/config-users
RUN /tmp/scripts/config-authselect && rm -r /tmp/scripts
```
### Systemd services
The first service completes the configuration during machine boot, which can't be done while building the container as it requires systemd to be running.

It sets the hostname:
```
HOST_NAME=kde-bootc
hostnamectl hostname $HOST_NAME
```
It creates the `systemd-homed` user `admin`:
```
homectl firstboot
```
And it sets up the firewall to allow kdeconnect to communicate:
```
firewall-cmd –set-default-zone=public
firewall-cmd --add-service=kdeconnect –permanent
```
The systemd unit will be placed, and enabled by default:
```
COPY --chmod=0644 ./systemd/usr__lib__systemd__system__firstboot-setup.service /usr/lib/systemd/system/firstboot-setup.service
RUN ln -s /usr/lib/systemd/system/firstboot-setup.service /usr/lib/systemd/system/default.target.wants/
```
The second service automates updates, replacing the default `bootc-fetch-apply-updates` service, which would download and apply updates as soon as they are available. This approach is problematic because it causes your computer to shut down without warning, so it is better to disable by masking the timer: 
```
RUN systemctl mask bootc-fetch-apply-updates.timer
```
The replacement `all-system-update` service will download the image from the registry, and queue it for the next reboot. It will also update Flatpak packages and, if present, update Toolbox. It is not enabled by default and can be turned on or off by the user as needed.
```
COPY --chmod=0644 ./systemd/usr__lib__systemd__system__all-system-update.service /usr/lib/systemd/system/all-system-update.service
COPY --chmod=0644 ./systemd/usr__lib__systemd__system__all-system-update.timer /usr/lib/systemd/system/all-system-update.timer
```
### Clean and Checks
This section focuses on cleaning the container before converting it into an image. The strategy includes using the latest `bootc container lint` option.
```
RUN find /var/log -type f ! -empty -delete
RUN bootc container lint
```
## How to create an ISO?
Creating an ISO to install your *kde-bootc* desktop is simple. First, build the container image either on GitHub or locally. 

Follow the instructions below to build the container locally, and ensure you do this as root so `bootc-image-builder` can use the image to make the ISO.
```
cd /path-to-your-repo
sudo podman build -t kde-bootc .
```
Then, outside the repository on a different directory, create a folder named `output` for the ISO image. Next, create the configuration file `config.toml` to be used by the installer.
```
./config.toml

[customizations.installer.kickstart]
contents = "graphical"
[customizations.installer.modules]
disable = [
  "org.fedoraproject.Anaconda.Modules.Users"
]
```
It instructs the installer to use the graphical interface and disable the module for user creation. We do not need to set up a user during installation, as this is already being taken care of.

To run the command, ensure you are in the directory containing the `./output` directory and `./config.toml` file. `bootc-image-builder` is self-contained, with all necessary configurations and packages, and must be run as root.
```
sudo podman run --rm -it --privileged --pull=newer \
--security-opt label=type:unconfined_t \
-v ./output:/output \
-v /var/lib/containers/storage:/var/lib/containers/storage \
-v ./config.toml:/config.toml:ro \
quay.io/centos-bootc/bootc-image-builder:latest \
--type iso \
--chown 1000:1000 \
localhost/kde-bootc
```
If everything goes as planned, the ISO image will be available in the `./output` directory.

For more information on `bootc-image-builder`, visit: https://github.com/osbuild/bootc-image-builder
## Post installation:
Once *kde-bootc* is installed, there are additional settings to improve usability. 

The first step is to restore the SELinux context for the `systemd-homed` home directory. Without this, you may not be able to log in as `admin`. To complete this task, log in as `root`, activate `admin` home area, and then run `restorecon` to restore the SELinux context. 
```
homectl activate admin
<< enter password for admin: Temp#SsaP
restorecon -R /home/admin
homectl deactivate admin
```
At this point, you can change the passwords for `root` and `admin`: 
```
passwd root
homectl passwd admin
```
After completing these steps, you can log out from `root` and log in to `admin`. 

If your computer has a fingerprint reader, setting it up is not possible from Plasma's user settings, as `systemd-homed` is not yet recognised by the desktop. However, you can manually enrol your fingerprint by running `fprintd-enroll` and placing your finger on the reader as you normally would. 
```
sudo fprintd-enroll admin
```
Same as above, you cannot set up the avatar from Plasma's user settings, but you can copy an available avatar (PNG file) from Plasma's avatar directory to the account service's directory. Ensure it is named the same as the username: 
```
/usr/share/plasma/avatars/<avatar.png> -> /var/lib/AccountsService/icons/admin
```
Finally, enable the service to keep your system updated and any other desired services: 
```
systemctl enable --now all-system-update.timer
systemctl enable --now tailscaled
```
To pull your image from a private GitHub repository using podman, copy `/usr/lib/ostree/auth.json` to `/home/admin/.config/containers/auth.json` for user space and `/root/.config/containers/auth.json` for root. It will allow you to use `podman pull ..` and `sudo podman pull ..` respectively.
## Troubleshooting
Please note that a configuration file in `/etc` drifts when it is modified locally. Consequently, bootc will no longer manage this file, and new releases won't be transferred to your installation. While this might be desired in some cases, it can also lead to issues. 

For instance, if `/etc/passwd` is locally modified, `uid` or `gid` allocations for services may not get updated, resulting in service failures. 

Use `ostree admin config-diff` to list the files in your local `/etc` that are no longer managed by bootc, because they were modified or added.

If a particular configuration file needs to be managed by bootc, you can revert it by copying the version created by the container build from `/usr/etc` to `/etc`.
