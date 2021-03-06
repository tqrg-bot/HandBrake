include Makefile.config

SYSTEM = $(shell uname -s)

# Special case for Mac OS X: everything is handled from the Xcode project

ifeq ($(SYSTEM),Darwin)

all:    clean app

all-chunky:    clean app-chunky

test:	clean cli

dev:	clean internal

app:
	(./DownloadMacOsXContribBinaries.sh ; cd macosx ; xcodebuild -target libhb -target HandBrake -target HandBrakeCLI -configuration UB  OTHER_CFLAGS_QUOTED_1="-DHB_VERSION=\\\"$(HB_VERSION)\\\" -DHB_BUILD=$(HB_BUILD) " build | sed '/^$$/d' ; cd .. ; ./macosx/localize.sh HandBrake.app $(HB_VERSION) $(HB_BUILD) UB )

app-chunky:
	(./DownloadMacOsXContribBinaries.sh ; cd macosx ; xcodebuild -alltargets -configuration UB  OTHER_CFLAGS_QUOTED_1="-DHB_VERSION=\\\"$(HB_VERSION)\\\" -DHB_BUILD=$(HB_BUILD) " build | sed '/^$$/d' ; cd .. ; ./macosx/localize.sh HandBrake.app $(HB_VERSION) $(HB_BUILD) UB )

cli:
	(./DownloadMacOsXContribBinaries.sh ; cd macosx ; xcodebuild -target libhb -target HandBrakeCLI -configuration UB  OTHER_CFLAGS_QUOTED_1="-DHB_VERSION=\\\"$(HB_VERSION)\\\" -DHB_BUILD=$(HB_BUILD) " build | sed '/^$$/d' )

clean:
	(cd macosx ; xcodebuild -alltargets -configuration UB clean | sed '/^$$/d' )

mrproper:
	(rm -rf contrib/*tar.gz contrib/include contrib/lib contrib/DarwinContribVersion.txt ; cd macosx ; xcodebuild -alltargets -configuration UB clean | sed '/^$$/d' )

release:
	(rm -rf HandBrake HandBrake*dmg ; mkdir -p HandBrake/api HandBrake/doc HandBrake/doc/pdf; cp test/BUILDSHARED AUTHORS BUILD COPYING CREDITS NEWS THANKS TRANSLATIONS HandBrake/doc ; cp -rp pdf/ HandBrake/doc/pdf/ ; cp -rp HandBrake.app HandBrake ; cp -rp libhb/libhb.dylib HandBrake/api ; cp -rp libhb/hb.h libhb/common.h libhb/ports.h HandBrake/api ; cp -rp HandBrakeCLI HandBrake ; hdiutil create -srcfolder HandBrake  -format UDZO HandBrake-$(HB_VERSION)-MacOS_UB.dmg ; rm -rf HandBrake )

endif

ifeq ($(SYSTEM),Linux)

all:	contrib/.contrib libhb/libhb.a HandBrakeCLI
	(rm -rf HandBrake HandBrake*.tar.gz ; mkdir -p HandBrake/api HandBrake/doc; cp test/BUILDSHARED AUTHORS BUILD COPYING CREDITS NEWS THANKS TRANSLATIONS HandBrake/doc ;  cp -rp libhb/libhb.so HandBrake/api ; cp -rp libhb/hb.h libhb/common.h libhb/ports.h HandBrake/api ; cp -rp HandBrakeCLI HandBrake ; tar zcvf HandBrake-$(HB_VERSION)_i386.tar.gz HandBrake ; rm -rf HandBrake )


contrib/.contrib:
	@$(MAKE) --no-print-directory -C contrib all

libhb/libhb.a:
	@$(MAKE) --no-print-directory -C libhb all

HandBrakeCLI:
	@$(MAKE) --no-print-directory -C test all

clean:
	@$(MAKE) --no-print-directory -C libhb clean
	@$(MAKE) --no-print-directory -C test clean

mrproper: clean
	@$(MAKE) --no-print-directory -C contrib mrproper

endif

ifeq ($(SYSTEM),CYGWIN_NT-5.1)

all:    contrib/.contrib libhb/libhb.a 


app:
	(./DownloadCygWinContribBinaries.sh)
HandbrakeCLI: app libhb/libhb.a


contrib/.contrib:
	@$(MAKE) --no-print-directory -C contrib all

libhb/libhb.a:
	@$(MAKE) --no-print-directory -C libhb all

HandbrakeCLI:
	@$(MAKE) --no-print-directory -C test all
	

	
clean:
	@$(MAKE) --no-print-directory -C libhb clean
	@$(MAKE) --no-print-directory -C test clean

mrproper: clean
	@$(MAKE) --no-print-directory -C contrib mrproper

endif
