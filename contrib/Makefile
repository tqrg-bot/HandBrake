# Contrib Makefile

SYSTEM = $(shell uname -s)

# Special case for Mac OS X: everything is handled from the Xcode project
ifeq ($(SYSTEM),Darwin)

all:
	( echo "MacOs X doesn't use this makefile, to build the contrib please use ../jam" ; false )

endif

ifeq ($(SYSTEM),Linux)

all:	.contrib

.contrib:
	( cd .. ; ./configure ; cd contrib ; cp -f ../config.jam . ; jam )

clean:	
	( echo "Do a make mrproper to remove the contrib libraries )

mrproper: 
	(rm -rf lib ; rm -rf include )

endif

ifeq ($(SYSTEM),CYGWIN_NT-5.1)

all:	.contrib

.contrib:    
	( cd .. ; ./configure ; cd contrib ; cp -f ../config.jam . ; jam.exe )

clean:
	( echo "Do a make mrproper to remove the contrib libraries )

mrproper: clean
	(rm -rf lib ; rm -rf include ; rm -f .contrib)

endif
