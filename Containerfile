FROM quay.io/fedora/fedora-bootc:42
MAINTAINER First Last

# SETUP FILESYSTEM
RUN rmdir /opt && ln -s -T /var/opt /opt
RUN mkdir /var/roothome

# PREPARE PACKAGES
COPY --chmod=0644 ./system/usr__local__share__kde-bootc__packages-removed /usr/local/share/kde-bootc/packages-removed
COPY --chmod=0644 ./system/usr__local__share__kde-bootc__packages-added /usr/local/share/kde-bootc/packages-added
RUN jq -r .packages[] /usr/share/rpm-ostree/treefile.json > /usr/local/share/kde-bootc/packages-fedora-bootc

# INSTALL REPOS
RUN dnf -y install dnf5-plugins
RUN dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo 

# INSTALL PACKAGES
RUN dnf -y install @kde-desktop-environment
RUN grep -vE '^#' /usr/local/share/kde-bootc/packages-added | xargs dnf -y install --allowerasing

# REMOVE PACKAGES
RUN grep -vE '^#' /usr/local/share/kde-bootc/packages-removed | xargs dnf -y remove
RUN dnf -y autoremove
RUN dnf clean all

# CONFIGURATION
COPY --chmod=0755 ./system/usr__local__bin/* /usr/local/bin/
COPY --chmod=0644 ./system/etc__skel__kde-bootc /etc/skel/.bashrc.d/kde-bootc
COPY --chmod=0600 ./system/usr__lib__ostree__auth.json /usr/lib/ostree/auth.json

# USERS
COPY --chmod=0644 ./system/usr__lib__credstore__home.create.admin /usr/lib/credstore/home.create.admin

COPY --chmod=0755 ./scripts/* /tmp/scripts/
RUN /tmp/scripts/config-users
RUN /tmp/scripts/config-authselect && rm -r /tmp/scripts

# SYSTEMD
COPY --chmod=0644 ./systemd/usr__lib__systemd__system__firstboot-setup.service /usr/lib/systemd/system/firstboot-setup.service
COPY --chmod=0644 ./systemd/usr__lib__systemd__system__bootc-fetch.service /usr/lib/systemd/system/bootc-fetch.service
COPY --chmod=0644 ./systemd/usr__lib__systemd__system__bootc-fetch.timer /usr/lib/systemd/system/bootc-fetch.timer

RUN ln -s /usr/lib/systemd/system/firstboot-setup.service /usr/lib/systemd/system/default.target.wants/
RUN systemctl mask bootc-fetch-apply-updates.timer

# CLEAN & CHECK
RUN find /var/log -type f ! -empty -delete
RUN bootc container lint
