.PHONY = all clean distclean install uninstall

prefix=/usr/local
bindir=$(prefix)/bin
datadir=/opt/wlanpi-common
default_prefix=/usr/local

install_data_dir = $(DESTDIR)$(datadir)
install_bin_dir = $(DESTDIR)$(bindir)

networkinfo_rel_dir = networkinfo

SERVICE_SUBS = \
	s,[@]bindir[@],$(bindir),g; \
	s,[@]datadir[@],$(datadir),g; \
	s,[@]networkinfo[@],$(datadir)/$(networkinfo_rel_dir),g

all:

networkinfo.service: networkinfo.service.in
	@echo "Set the prefix on networkinfo.service"
	sed -e '$(SERVICE_SUBS)' $< > $@

install: installdirs networkinfo-links networkinfo.service
	cp -rf $(filter-out debian Makefile networkinfo.service.in $^,$(wildcard *)) $(install_data_dir)
	install -m 644 networkinfo.service $(DESTDIR)/lib/systemd/system

installdirs:
	mkdir -p $(install_bin_dir) \
		$(install_data_dir) \
		$(DESTDIR)/lib/systemd/system

networkinfo-links:
	ln -fs $(install_data_dir)/$(networkinfo_rel_dir)/reachability.sh $(install_bin_dir)/reachability
	ln -fs $(install_data_dir)/$(networkinfo_rel_dir)/publicip.sh $(install_bin_dir)/publicip
	ln -fs $(install_data_dir)/$(networkinfo_rel_dir)/watchinternet.sh $(install_bin_dir)/watchinternet
	ln -fs $(install_data_dir)/$(networkinfo_rel_dir)/telegrambot.sh $(install_bin_dir)/telegrambot
	ln -fs $(install_data_dir)/$(networkinfo_rel_dir)/ipconfig.sh $(install_bin_dir)/ipconfig
	ln -fs $(install_data_dir)/$(networkinfo_rel_dir)/portblinker.sh $(install_bin_dir)/portblinker

clean:
	-rm -f networkinfo.service

distclean: clean

uninstall:
	-rm -rf $(install_data_dir) \
		$(DESTDIR)/lib/systemd/system \
		$(bindir)/reachability \
		$(bindir)/publicip \
		$(bindir)/watchinternet \
		$(bindir)/telegrambot \
		$(bindir)/ipconfig \
		$(bindir)/portblinker

