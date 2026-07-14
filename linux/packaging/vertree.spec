%global app_id dev.w0fv1.vertree
%global debug_package %{nil}

Name:           vertree
Version:        @RPM_VERSION@
Release:        @RPM_RELEASE@
Summary:        Single-file version manager for backup, monitoring, and version trees

License:        MIT
URL:            https://vertree.w0fv1.dev
Source0:        %{name}-%{version}.tar.gz
Source1:        vertree.desktop
Source2:        vertree.png
Source3:        vertree.sh
Source4:        vertree.metainfo.xml
Source5:        vertree_nautilus.py

BuildArch:      x86_64
Recommends:     nautilus-python

%description
Vertree is a desktop application for single-file version management. It
supports manual backups, quick backups, file monitoring, and visual version
tree inspection for files that do not fit a Git-based workflow.










%prep
%autosetup -n %{name}-%{version}

%build


%install
rm -rf %{buildroot}

install -d %{buildroot}%{_libexecdir}/vertree
cp -a bundle/. %{buildroot}%{_libexecdir}/vertree/

install -Dpm0755 %{SOURCE3} %{buildroot}%{_bindir}/vertree
install -Dpm0644 %{SOURCE1} %{buildroot}%{_datadir}/applications/%{app_id}.desktop
install -Dpm0644 %{SOURCE2} %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/vertree.png
install -Dpm0644 %{SOURCE2} %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/vertree.png
install -Dpm0644 %{SOURCE4} %{buildroot}%{_datadir}/metainfo/%{app_id}.metainfo.xml
install -Dpm0644 %{SOURCE5} %{buildroot}%{_datadir}/nautilus-python/extensions/vertree_extension.py

desktop-file-install \
  --dir=%{buildroot}%{_datadir}/applications \
  %{buildroot}%{_datadir}/applications/%{app_id}.desktop

appstreamcli validate --no-net %{buildroot}%{_datadir}/metainfo/%{app_id}.metainfo.xml

%files
%license LICENSE
%{_bindir}/vertree
%{_libexecdir}/vertree
%{_datadir}/applications/%{app_id}.desktop
%{_datadir}/icons/hicolor/256x256/apps/vertree.png
%{_datadir}/icons/hicolor/512x512/apps/vertree.png
%{_datadir}/metainfo/%{app_id}.metainfo.xml
%{_datadir}/nautilus-python/extensions/vertree_extension.py

%changelog
* @CHANGELOG_DATE@ w0fv1 <wofbi1@outlook.com> - @RAW_VERSION@-1
- Improve RPM packaging for GitHub Actions and prerelease builds
