#**************************************************************************************#
#
# GNUstep makefile to build OSXFUSE/framework for the GNUstep environment
#
# See http://www.gnustep.org/resources/documentation/Developer/Make/Manual/make_toc.html
#    for details about the GNUstep Makefile system
#
#**************************************************************************************#

# Include the common variables defined by the Makefile Package
include $(GNUSTEP_MAKEFILES)/common.make

# Build a framework project.
# Note: There is not much documentation. Read $GNUSTEP_MAKEFILES/Instance/framework.make for information
FRAMEWORK_NAME = OSXFUSE

# Framework compiled version name (default "0")
#$(FRAMEWORK_NAME)_CURRENT_VERSION_NAME =

# Framework version being built should be made the current/default? (default is yes)
#$(FRAMEWORK_NAME)_MAKE_CURRENT_VERSION	=

# Framework needs GUI (AppKit graphical application) support? (default is yes)
$(FRAMEWORK_NAME)_NEEDS_GUI	= no

# Framework subprojects
#$(FRAMEWORK_NAME)_SUBPROJECTS	=

# Framework preprocessor, compiler and linker flags and include directories
$(FRAMEWORK_NAME)_INCLUDE_DIRS	=
$(FRAMEWORK_NAME)_CPPFLAGS 		= -D_FILE_OFFSET_BITS=64
$(FRAMEWORK_NAME)_CFLAGS 		=
$(FRAMEWORK_NAME)_OBJCFLAGS 	=

# Linux requires libfuse
ifeq ($(GNUSTEP_HOST_OS), linux-gnu)
$(FRAMEWORK_NAME)_LDFLAGS		= -v -lfuse
endif

# Framework principal class
#$(FRAMEWORK_NAME)_PRINCIPAL_CLASS	=

# Framework Info-gnustep.plist is automatically genereated. Custom entries can be provided
#	in $(FRAMEWORK_NAME)Info.plist and will be automatically merged

# Framework header directory (default == ./) and files
#$(FRAMEWORK_NAME)_HEADER_FILES_DIR	=
$(FRAMEWORK_NAME)_HEADER_FILES 		= OSXFUSE.h \
										GMAvailability.h \
										GMFinderInfo.h \
										GMResourceFork.h \
										GMUserFileSystem.h

# Framework header file installation directory inside the framework installation directory.
#	(defaults to the framework name [without .framework]).  Can't be `.'
#
#	The HEADER_FILES_INSTALL_DIR might look somewhat weird - because in
# 	most if not all cases, you want it to be the framework name.  At the
# 	moment, it allows you to put headers for framework XXX in directory
# 	YYY, so that you can refer to them by using #include
# 	<YYY/MyHeader.h> rather than #include <XXX/MyHeader.h>.  It seems to
# 	be mostly used to have a framework with name XXX work as a drop-in
# 	replacement for another framework, which has name YYY -- and which
# 	might be installed at the same time.
#$(FRAMEWORK_NAME)_HEADER_FILES_INSTALL_DIR	=

# Framework Objective C files
$(FRAMEWORK_NAME)_OBJC_FILES 	= GMDataBackedFileDelegate.m \
									GMFinderInfo.m \
									GMResourceFork.m \
									GMUserFileSystem.m


# Framework tests directory. 'make check' will cause tests to be run using gnustep-tests.
#$(FRAMEWORK_NAME)_TEST_DIR	=

# Framework resource directories and files
#$(FRAMEWORK_NAME)_RESOURCE_DIRS	=
#$(FRAMEWORK_NAME)_RESOURCE_FILES	=

# Framework webserver GSWeb components
#$(FRAMEWORK_NAME)_COMPONENTS	=

# Framework webserver resource directories and files
#$(FRAMEWORK_NAME)_WEBSERVER_RESOURCE_DIRS	=
#$(FRAMEWORK_NAME)_WEBSERVER_RESOURCE_FILES	=

# Framework languages
# $(FRAMEWORK_NAME)_LANGUAGES =

# Framework localised resource files
#$(FRAMEWORK_NAME)_LOCALIZED_RESOURCE_FILES =

# Framework localised webserver resource diretories and files
#$(FRAMEWORK_NAME)_WEBSERVER_LOCALIZED_RESOURCE_DIRS	=
#$(FRAMEWORK_NAME)_WEBSERVER_LOCALIZED_RESOURCE_FILES 	=

include $(GNUSTEP_MAKEFILES)/framework.make
