# Enable secondary expansions, needed for font compilation rules
.SECONDEXPANSION:

SRC := $(abspath $(SRCDIR))
OBJ := $(abspath $(CURDIR))

ifeq ($(filter s,$(MAKEFLAGS)),s)
MAKEFLAGS += --quiet --no-print-directory
--quiet? := --quiet
else
MFLAGS += V=1 VERBOSE=1
-v? := -v
--verbose? := --verbose
endif

##
## Nested make
##

SHELL := /bin/bash

ifneq ($(NO_NESTED_MAKE),1)
# Pass all variables/goals to ourselves as a sub-make such that we will get a trailing error message upon failure.  (We
# invoke a lot of long-running build-steps, and make fails to re-print errors when they happened ten thousand lines
# ago.)
export
.DEFAULT_GOAL := default
.PHONY: $(MAKECMDGOALS) default nested_make
default $(MAKECMDGOALS): nested_make

nested_make:
	+$(MAKE) $(MAKECMDGOALS) -f $(firstword $(MAKEFILE_LIST)) NO_NESTED_MAKE=1

else # (Rest of the file is the else)

##
## General/global config
##

# We expect the configure script to conditionally set the following:
#   SRCDIR          - Path to source
#   BUILD_NAME      - Name of the build for manifests etc.
#   STEAMRT_IMAGE   - Name of the docker image to use for building
#   STEAMRT_NAME    - Name of the steam runtime to build against (scout / soldier)

ifeq ($(SRCDIR),)
	foo := $(error SRCDIR not set, do not include makefile_base directly, run ./configure.sh to generate Makefile)
endif

include $(SRC)/make/utility.mk
include $(SRC)/make/rules-source.mk
include $(SRC)/make/rules-common.mk
include $(SRC)/make/rules-cmake.mk
include $(SRC)/make/rules-autoconf.mk
include $(SRC)/make/rules-winemaker.mk
include $(SRC)/make/rules-cargo.mk

# If CC is coming from make's defaults or nowhere, use our own default.  Otherwise respect environment.
CCACHE_ENV := $(patsubst %,-e %,$(shell env|cut -d= -f1|grep '^CCACHE_'))
ifeq ($(ENABLE_CCACHE),1)
	CCACHE_BIN := ccache
	export CCACHE_DIR := $(if $(CCACHE_DIR),$(CCACHE_DIR),$(HOME)/.ccache)
	DOCKER_OPTS := -v $(CCACHE_DIR):$(CCACHE_DIR)$(CONTAINER_MOUNT_OPTS) $(CCACHE_ENV) -e CCACHE_DIR=$(CCACHE_DIR) $(DOCKER_OPTS)
else
	export CCACHE_DISABLE := 1
	DOCKER_OPTS := $(CCACHE_ENV) -e CCACHE_DISABLE=1 $(DOCKER_OPTS)
endif

ifneq ($(ROOTLESS_CONTAINER),1)
	DOCKER_OPTS := -e HOME -e USER -e USERID=$(shell id -u) -u $(shell id -u):$(shell id -g) $(DOCKER_OPTS)
endif

ifeq ($(CONTAINER_ENGINE),)
	CONTAINER_ENGINE := docker
endif

DOCKER_BASE = $(CONTAINER_ENGINE) run --rm -v $(SRC):$(SRC)$(CONTAINER_MOUNT_OPTS) -v $(OBJ):$(OBJ)$(CONTAINER_MOUNT_OPTS) \
                -w $(OBJ) -e MAKEFLAGS \
                $(DOCKER_OPTS) $(STEAMRT_IMAGE)

STEAMRT_NAME ?= soldier
ifeq ($(STEAMRT_NAME),soldier)
TOOLMANIFEST_VDF_SRC := toolmanifest_runtime.vdf
else
TOOLMANIFEST_VDF_SRC := toolmanifest_noruntime.vdf
endif

ifneq ($(STEAMRT_IMAGE),)
CONTAINER_SHELL := $(DOCKER_BASE) /bin/bash
STEAM_RUNTIME_RUNSH := $(DOCKER_BASE)
else
CONTAINER_SHELL := $(SHELL)
STEAM_RUNTIME_RUNSH :=
endif


MAKECMDGOALS32 := $(filter-out all32,$(filter %32,$(MAKECMDGOALS)))
MAKECMDGOALS64 := $(filter-out all64,$(filter %64,$(MAKECMDGOALS)))
CONTAINERGOALS := $(MAKECMDGOALS32) $(MAKECMDGOALS64)

all: all32 all64
.PHONY: all

all32 $(MAKECMDGOALS32):
.PHONY: all32 $(MAKECMDGOALS32)

all32 $(MAKECMDGOALS64):
.PHONY: all64 $(MAKECMDGOALS64)

ifeq ($(CONTAINER),)
J := $(shell nproc)
ifeq ($(ENABLE_CCACHE),1)
container-build: $(shell mkdir -p $(CCACHE_DIR))
endif
container-build: private SHELL := $(CONTAINER_SHELL)
container-build:
	+$(MAKE) -j$(J) $(filter -j%,$(MAKEFLAGS)) -f $(firstword $(MAKEFILE_LIST)) $(MFLAGS) $(MAKEOVERRIDES) CONTAINER=1 $(CONTAINERGOALS)
.PHONY: container-build

all32 $(MAKECMDGOALS32): container-build
all64 $(MAKECMDGOALS64): container-build
else
J = $(patsubst -j%,%,$(filter -j%,$(MAKEFLAGS)))
endif


.PHONY: test-container
test-container:
	@echo >&2 ":: Testing container"
	$(CONTAINER_SHELL) -c "echo Hello World!"

# Many of the configure steps below depend on the makefile itself, such that they are dirtied by changing the recipes
# that create them.  This can be annoying when working on the makefile, building with NO_MAKEFILE_DEPENDENCY=1 disables
# this.
MAKEFILE_DEP := $(MAKEFILE_LIST)
ifeq ($(NO_MAKEFILE_DEPENDENCY),1)
MAKEFILE_DEP :=
endif

##
## Global config
##

DST_BASE := $(OBJ)/dist
DST_DIR := $(DST_BASE)/files
DST_LIBDIR32 := $(DST_DIR)/lib
DST_LIBDIR64 := $(DST_DIR)/lib64
DEPLOY_DIR := ./deploy
REDIST_DIR := ./redist

# All top level goals.  Lazy evaluated so they can be added below.
GOAL_TARGETS = $(GOAL_TARGETS_LIBS)
# Excluding goals like wine and dist that are either long running or slow per invocation
GOAL_TARGETS_LIBS =
# Any explicit thing, superset
ALL_TARGETS =

##
## Platform-specific variables
##

ifneq ($(UNSTRIPPED_BUILD),)
    STRIP :=
    INSTALL_PROGRAM_FLAGS :=
else
    STRIP := strip
    INSTALL_PROGRAM_FLAGS := -s
endif

CROSSLDFLAGS   += -Wl,--file-alignment,4096
OPTIMIZE_FLAGS := -O2 -march=nocona -mtune=core-avx2 -mfpmath=sse
SANITY_FLAGS   := -fwrapv -fno-strict-aliasing
DEBUG_FLAGS    := -gdwarf-2 -gstrict-dwarf
COMMON_FLAGS    = $(DEBUG_FLAGS) $(OPTIMIZE_FLAGS) $(SANITY_FLAGS) -ffile-prefix-map=$(CCACHE_BASEDIR)=.
COMMON_FLAGS32 := -mstackrealign
CARGO_BUILD_ARG := --release

##
## Target configs
##

COMPAT_MANIFEST_TEMPLATE := $(SRCDIR)/compatibilitytool.vdf.template
LICENSE := $(SRCDIR)/dist.LICENSE
STEAMPIPE_FIXUPS_PY := $(SRCDIR)/steampipe_fixups.py

GECKO_VER := 2.47.2
GECKO32_TARBALL := wine-gecko-$(GECKO_VER)-x86.tar.xz
GECKO64_TARBALL := wine-gecko-$(GECKO_VER)-x86_64.tar.xz

WINEMONO_VER := 6.3.0
WINEMONO_TARBALL := wine-mono-$(WINEMONO_VER)-x86.tar.xz

ifeq ($(CONTAINER),)

## downloads -- Convenience target to download packages used during the build
## process. Places them in subdirs one up from the Proton source dir, so
## they won't be wiped during git-clean, vagrant rsync, etc.

.PHONY: downloads

GECKO64_TARBALL_URL := https://dl.winehq.org/wine/wine-gecko/$(GECKO_VER)/$(GECKO64_TARBALL)
GECKO32_TARBALL_URL := https://dl.winehq.org/wine/wine-gecko/$(GECKO_VER)/$(GECKO32_TARBALL)
MONO_TARBALL_URL := https://github.com/madewokherd/wine-mono/releases/download/wine-mono-$(WINEMONO_VER)/$(WINEMONO_TARBALL)

SHARED_GECKO64_TARBALL := $(SRCDIR)/../gecko/$(GECKO64_TARBALL)
SHARED_GECKO32_TARBALL := $(SRCDIR)/../gecko/$(GECKO32_TARBALL)
SHARED_MONO_TARBALL := $(SRCDIR)/../mono/$(WINEMONO_TARBALL)

$(SHARED_GECKO64_TARBALL):
	mkdir -p $(dir $@)
	wget -O "$@" "$(GECKO64_TARBALL_URL)"

$(SHARED_GECKO32_TARBALL):
	mkdir -p $(dir $@)
	wget -O "$@" "$(GECKO32_TARBALL_URL)"

$(SHARED_MONO_TARBALL):
	mkdir -p $(dir $@)
	wget -O "$@" "$(MONO_TARBALL_URL)"

downloads: $(SHARED_GECKO64_TARBALL) $(SHARED_GECKO32_TARBALL) $(SHARED_MONO_TARBALL)

##
## dist/install -- steps to finalize the install
##

$(DST_DIR):
	mkdir -p $@

STEAM_DIR := $(HOME)/.steam/root

FILELOCK_TARGET := $(addprefix $(DST_BASE)/,filelock.py)
$(FILELOCK_TARGET): $(addprefix $(SRCDIR)/,filelock.py)

PROTON_PY_TARGET := $(addprefix $(DST_BASE)/,proton)
$(PROTON_PY_TARGET): $(addprefix $(SRCDIR)/,proton)

PROTON37_TRACKED_FILES_TARGET := $(addprefix $(DST_BASE)/,proton_3.7_tracked_files)
$(PROTON37_TRACKED_FILES_TARGET): $(addprefix $(SRCDIR)/,proton_3.7_tracked_files)

USER_SETTINGS_PY_TARGET := $(addprefix $(DST_BASE)/,user_settings.sample.py)
$(USER_SETTINGS_PY_TARGET): $(addprefix $(SRCDIR)/,user_settings.sample.py)

PROTONFIXES_TARGET := $(addprefix $(DST_BASE)/,protonfixes)
$(PROTONFIXES_TARGET): $(addprefix $(SRCDIR)/,protonfixes)

DIST_COPY_TARGETS := $(FILELOCK_TARGET) $(PROTON_PY_TARGET) \
                     $(PROTON37_TRACKED_FILES_TARGET) $(USER_SETTINGS_PY_TARGET) \
                     $(PROTONFIXES_TARGET)

DIST_VERSION := $(DST_BASE)/version
DIST_PREFIX := $(DST_DIR)/share/default_pfx/
DIST_COMPAT_MANIFEST := $(DST_BASE)/compatibilitytool.vdf
DIST_LICENSE := $(DST_BASE)/LICENSE
DIST_TOOLMANIFEST := $(addprefix $(DST_BASE)/,toolmanifest.vdf)
DIST_GECKO_DIR := $(DST_DIR)/share/wine/gecko
DIST_GECKO32 := $(DIST_GECKO_DIR)/wine-gecko-$(GECKO_VER)-x86
DIST_GECKO64 := $(DIST_GECKO_DIR)/wine-gecko-$(GECKO_VER)-x86_64
DIST_WINEMONO_DIR := $(DST_DIR)/share/wine/mono
DIST_WINEMONO := $(DIST_WINEMONO_DIR)/wine-mono-$(WINEMONO_VER)

DIST_TARGETS := $(DIST_COPY_TARGETS) $(DIST_OVR32) $(DIST_OVR64) \
                $(DIST_GECKO32) $(DIST_GECKO64) $(DIST_WINEMONO) \
                $(DIST_COMPAT_MANIFEST) $(DIST_LICENSE) $(DIST_TOOLMANIFEST)

BASE_COPY_TARGETS := $(DIST_COPY_TARGETS) $(DIST_VERSION) $(DIST_LICENSE) $(DIST_TOOLMANIFEST) $(DST_DIR)
DEPLOY_COPY_TARGETS := $(BASE_COPY_TARGETS) $(STEAMPIPE_FIXUPS_PY)
REDIST_COPY_TARGETS := $(BASE_COPY_TARGETS) $(DIST_COMPAT_MANIFEST)

$(DIST_LICENSE): $(LICENSE)
	cp -a $< $@

$(DIST_TOOLMANIFEST): $(addprefix $(SRCDIR)/,$(TOOLMANIFEST_VDF_SRC))
	cp -a $< $@

$(DIST_COPY_TARGETS): | $(DST_DIR)
	cp -a $(SRCDIR)/$(notdir $@) $@

$(DIST_COMPAT_MANIFEST): $(COMPAT_MANIFEST_TEMPLATE) $(MAKEFILE_DEP) | $(DST_DIR)
	sed -r 's|##BUILD_NAME##|$(BUILD_NAME)|' $< > $@

$(DIST_GECKO_DIR):
	mkdir -p $@

$(DIST_GECKO64): | $(DIST_GECKO_DIR)
	if [ -e "$(SHARED_GECKO64_TARBALL)" ]; then \
		tar -xf "$(SHARED_GECKO64_TARBALL)" -C "$(dir $@)"; \
	else \
		mkdir -p $(SRCDIR)/contrib/; \
		if [ ! -e "$(SRCDIR)/contrib/$(GECKO64_TARBALL)" ]; then \
			echo ">>>> Downloading wine-gecko. To avoid this in future, put it here: $(SRCDIR)/../gecko/$(GECKO64_TARBALL)"; \
			wget -O "$(SRCDIR)/contrib/$(GECKO64_TARBALL)" "$(GECKO64_TARBALL_URL)"; \
		fi; \
		tar -xf "$(SRCDIR)/contrib/$(GECKO64_TARBALL)" -C "$(dir $@)"; \
	fi

$(DIST_GECKO32): | $(DIST_GECKO_DIR)
	if [ -e "$(SHARED_GECKO32_TARBALL)" ]; then \
		tar -xf "$(SHARED_GECKO32_TARBALL)" -C "$(dir $@)"; \
	else \
		mkdir -p $(SRCDIR)/contrib/; \
		if [ ! -e "$(SRCDIR)/contrib/$(GECKO32_TARBALL)" ]; then \
			echo ">>>> Downloading wine-gecko. To avoid this in future, put it here: $(SRCDIR)/../gecko/$(GECKO32_TARBALL)"; \
			wget -O "$(SRCDIR)/contrib/$(GECKO32_TARBALL)" "$(GECKO32_TARBALL_URL)"; \
		fi; \
		tar -xf "$(SRCDIR)/contrib/$(GECKO32_TARBALL)" -C "$(dir $@)"; \
	fi

$(DIST_WINEMONO_DIR):
	mkdir -p $@

$(DIST_WINEMONO): | $(DIST_WINEMONO_DIR)
	if [ -e "$(SHARED_MONO_TARBALL)" ]; then \
		tar -xf "$(SHARED_MONO_TARBALL)" -C "$(dir $@)"; \
	else \
		mkdir -p $(SRCDIR)/contrib/; \
		if [ ! -e "$(SRCDIR)/contrib/$(WINEMONO_TARBALL)" ]; then \
			echo ">>>> Downloading wine-mono. To avoid this in future, put it here: $(SRCDIR)/../mono/$(WINEMONO_TARBALL)"; \
			wget -O "$(SRCDIR)/contrib/$(WINEMONO_TARBALL)" "$(MONO_TARBALL_URL)"; \
		fi; \
		tar -xf "$(SRCDIR)/contrib/$(WINEMONO_TARBALL)" -C "$(dir $@)"; \
	fi

.PHONY: dist

ALL_TARGETS += dist
GOAL_TARGETS += dist

dist_prefix: wine gst_good
	find $(DST_LIBDIR32)/wine -type f -execdir chmod a-w '{}' '+'
	find $(DST_LIBDIR64)/wine -type f -execdir chmod a-w '{}' '+'
	rm -rf $(abspath $(DIST_PREFIX))
	python3 $(SRCDIR)/default_pfx.py $(abspath $(DIST_PREFIX)) $(abspath $(DST_DIR)) $(STEAM_RUNTIME_RUNSH)

# Dummy OpenXR
dist_wineopenxr: dist_prefix

dist: $(DIST_TARGETS) all-dist dist_wineopenxr | $(DST_DIR)
	echo `date '+%s'` `GIT_DIR=$(abspath $(SRCDIR)/.git) git describe --tags` > $(DIST_VERSION)

deploy: dist | $(filter-out dist deploy install redist,$(MAKECMDGOALS))
	mkdir -p $(DEPLOY_DIR)
	cp -af --no-dereference --preserve=mode,links $(DEPLOY_COPY_TARGETS) $(DEPLOY_DIR)
	python3 $(STEAMPIPE_FIXUPS_PY) process $(DEPLOY_DIR)

install: dist | $(filter-out dist deploy install redist,$(MAKECMDGOALS))
	if [ ! -d $(STEAM_DIR) ]; then echo >&2 "!! "$(STEAM_DIR)" does not exist, cannot install"; return 1; fi
	mkdir -p $(STEAM_DIR)/compatibilitytools.d/$(BUILD_NAME)
	cp -af --no-dereference --preserve=mode,links $(DST_BASE)/* $(STEAM_DIR)/compatibilitytools.d/$(BUILD_NAME)
	@echo "Installed Proton to "$(STEAM_DIR)/compatibilitytools.d/$(BUILD_NAME)
	@echo "You may need to restart Steam to select this tool"

redist: dist | $(filter-out dist deploy install redist,$(MAKECMDGOALS))
	mkdir -p $(REDIST_DIR)
	cp -af --no-dereference --preserve=mode,links $(REDIST_COPY_TARGETS) $(REDIST_DIR)

.PHONY: module32 module64 module

module32: private SHELL := $(CONTAINER_SHELL)
module32: CONTAINERGOALS := $(CONTAINERGOALS) wine-configure32
module32: | all-source wine-configure32
	+$(MAKE) -j$(J) $(filter -j%,$(MAKEFLAGS)) $(MFLAGS) $(MAKEOVERRIDES) -C $(WINE_OBJ32)/dlls/$(module) && \
	find $(WINE_OBJ32)/dlls/$(module) -type f -name '*.dll' -printf '%p\0' | \
	    xargs $(--verbose?) -0 -r -P$(J) -n1 $(SRC)/make/pefixup.py

module64: private SHELL := $(CONTAINER_SHELL)
module64: CONTAINERGOALS := $(CONTAINERGOALS) wine-configure64
module64: | all-source wine-configure64
	+$(MAKE) -j$(J) $(filter -j%,$(MAKEFLAGS)) $(MFLAGS) $(MAKEOVERRIDES) -C $(WINE_OBJ64)/dlls/$(module) && \
	find $(WINE_OBJ64)/dlls/$(module) -type f -name '*.dll' -printf '%p\0' | \
	    xargs $(--verbose?) -0 -r -P$(J) -n1 $(SRC)/make/pefixup.py

module: CONTAINERGOALS := $(CONTAINERGOALS) wine-configure
module: | all-source wine-configure
module: module32 module64

endif # ifeq ($(CONTAINER),)



##
## lsteamclient
##

LSTEAMCLIENT_CFLAGS = -Wno-attributes
LSTEAMCLIENT_CXXFLAGS = -Wno-attributes
LSTEAMCLIENT_LDFLAGS = -static-libgcc -static-libstdc++ -ldl

LSTEAMCLIENT_WINEMAKER_ARGS = \
	-DSTEAM_API_EXPORTS \
	-Dprivate=public \
	-Dprotected=public

LSTEAMCLIENT_DEPENDS = wine

$(eval $(call rules-source,lsteamclient,$(SRCDIR)/lsteamclient))
$(eval $(call rules-winemaker,lsteamclient,32,lsteamclient.dll))
$(eval $(call rules-winemaker,lsteamclient,64,lsteamclient.dll))

##
## steam.exe
##

STEAMEXE_CFLAGS = -Wno-attributes
STEAMEXE_CXXFLAGS = -Wno-attributes
STEAMEXE_LDFLAGS = -lsteam_api -lole32 -ldl -static-libgcc -static-libstdc++

STEAMEXE_WINEMAKER_ARGS = \
	"-I$(SRC)/lsteamclient/steamworks_sdk_142/" \
	"-L$(SRC)/steam_helper/"

STEAMEXE_DEPENDS = wine

$(eval $(call rules-source,steamexe,$(SRCDIR)/steam_helper))
$(eval $(call rules-winemaker,steamexe,32,steam.exe))

$(OBJ)/.steamexe-post-build32:
	cp $(STEAMEXE_SRC)/libsteam_api.so $(DST_LIBDIR32)/
	touch $@


##
## wine
##

WINE_SOURCE_ARGS = \
  --exclude configure \
  --exclude autom4te.cache \
  --exclude include/config.h.in \

WINE_CONFIGURE_ARGS = \
  --with-mingw \
  --disable-tests

WINE_CONFIGURE_ARGS64 = --enable-win64

WINE_DEPENDS = 

$(eval $(call rules-source,wine,$(SRCDIR)/wine))
$(eval $(call rules-autoconf,wine,32))
$(eval $(call rules-autoconf,wine,64))

$(WINE_SRC)/configure: $(SRCDIR)/wine/configure.ac | $(OBJ)/.wine-source
	cd $(WINE_SRC) && autoreconf -fi
	touch $@

$(OBJ)/.wine-post-source: $(WINE_SRC)/configure
	cd $(WINE_SRC) && dlls/winevulkan/make_vulkan
	cd $(WINE_SRC) && tools/make_requests
	touch $@

$(OBJ)/.wine-post-build64:
	mkdir -p $(DST_DIR)/{bin,share}
	$(call install-strip,$(WINE_DST64)/bin/wine64,$(DST_DIR)/bin)
	$(call install-strip,$(WINE_DST64)/bin/wine64-preloader,$(DST_DIR)/bin)
	$(call install-strip,$(WINE_DST64)/bin/wineserver,$(DST_DIR)/bin)
	cp -a $(WINE_DST64)/share/wine $(DST_DIR)/share
	cp -a $(WINE_DST64)/bin/msidb $(DST_DIR)/bin
	touch $@

$(OBJ)/.wine-post-build32:
	mkdir -p $(DST_DIR)/bin
	$(call install-strip,$(WINE_DST32)/bin/wine,$(DST_DIR)/bin)
	$(call install-strip,$(WINE_DST32)/bin/wine-preloader,$(DST_DIR)/bin)
	touch $@


ifeq ($(CONTAINER),)

##
## Targets
##

.PHONY: all all64 all32 default help targets

# Produce a working dist directory by default
default: all dist
.DEFAULT_GOAL := default

# For suffixes 64/32/_configure64/_configure32 automatically check if they exist compared to ALL_TARGETS and make
# all_configure32/etc aliases
GOAL_TARGETS64           := $(filter $(addsuffix 64,$(GOAL_TARGETS)),$(ALL_TARGETS))
GOAL_TARGETS32           := $(filter $(addsuffix 32,$(GOAL_TARGETS)),$(ALL_TARGETS))
GOAL_TARGETS_LIBS64      := $(filter $(addsuffix 64,$(GOAL_TARGETS_LIBS)),$(ALL_TARGETS))
GOAL_TARGETS_LIBS32      := $(filter $(addsuffix 32,$(GOAL_TARGETS_LIBS)),$(ALL_TARGETS))
GOAL_TARGETS_CONFIGURE   := $(filter $(addsuffix _configure,$(GOAL_TARGETS)),$(ALL_TARGETS))
GOAL_TARGETS_CONFIGURE64 := $(filter $(addsuffix _configure64,$(GOAL_TARGETS)),$(ALL_TARGETS))
GOAL_TARGETS_CONFIGURE32 := $(filter $(addsuffix _configure32,$(GOAL_TARGETS)),$(ALL_TARGETS))

# Anything in all-targets that didn't end up in here
OTHER_TARGETS := $(filter-out $(ALL_TARGETS),$(GOAL_TARGETS) $(GOAL_TARGETS64) $(GOAL_TARGETS32) \
                                             $(GOAL_TARGETS_LIBS64) $(GOAL_TARGETS_LIBS32) $(GOAL_TARGETS_CONFIGURE) \
                                             $(GOAL_TARGETS_CONFIGURE64) $(GOAL_TARGETS_CONFIGURE32))

help: targets
targets:
	$(info Default targets      (make all):              $(strip $(GOAL_TARGETS)))
	$(info Default targets      (make all_lib):          $(strip $(GOAL_TARGETS_LIBS)))
	$(info Default targets      (make all_configure):    $(strip $(GOAL_TARGETS_CONFIGURE)))
	$(info Default targets      (make all64):            $(strip $(GOAL_TARGETS64)))
	$(info Default targets      (make all32):            $(strip $(GOAL_TARGETS32)))
	$(info Default targets      (make all64_lib):        $(strip $(GOAL_TARGETS_LIBS64)))
	$(info Default targets      (make all32_lib):        $(strip $(GOAL_TARGETS_LIBS32)))
	$(info Reconfigure targets  (make all64_configure):  $(strip $(GOAL_TARGETS_CONFIGURE64)))
	$(info Reconfigure targets  (make all32_configure):  $(strip $(GOAL_TARGETS_CONFIGURE32)))
	$(info Other targets:    $(OTHER_TARGETS))

# All target
all: $(GOAL_TARGETS)
	@echo ":: make $@ succeeded"

all32: $(GOAL_TARGETS32)
	@echo ":: make $@ succeeded"

all64: $(GOAL_TARGETS64)
	@echo ":: make $@ succeeded"

# Libraries (not wine) only -- wine has a length install step that runs unconditionally, so this is useful for updating
# incremental builds when not iterating on wine itself.
all_lib: $(GOAL_TARGETS_LIBS)
	@echo ":: make $@ succeeded"

all32_lib: $(GOAL_TARGETS_LIBS32)
	@echo ":: make $@ succeeded"

all64_lib: $(GOAL_TARGETS_LIBS64)
	@echo ":: make $@ succeeded"

# Explicit reconfigure all targets
all_configure: $(GOAL_TARGETS_CONFIGURE)
	@echo ":: make $@ succeeded"

all32_configure: $(GOAL_TARGETS_CONFIGURE32)
	@echo ":: make $@ succeeded"

all64_configure: $(GOAL_TARGETS_CONFIGURE64)
	@echo ":: make $@ succeeded"

endif # ifeq ($(CONTAINER),)
endif # End of NESTED_MAKE from beginning
