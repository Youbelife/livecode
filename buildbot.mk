# Copyright (C) 2015 Runtime Revolution Ltd.
#
# This file is part of LiveCode.
#
# LiveCode is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License v3 as published by the Free
# Software Foundation.
#
# LiveCode is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with LiveCode.  If not see <http://www.gnu.org/licenses/>.

# This file contains rules used by the LiveCode Buildbot installation at
# <https://vulcan.livecode.com/>

################################################################
# Configure with gyp
################################################################

# Buildbot must set the variables PLATFORM and SUBPLATFORM

ifeq ($(BUILD_SUBPLATFORM),)
CONFIG_TARGET = config-$(BUILD_PLATFORM)
else
CONFIG_TARGET = config-$(BUILD_PLATFORM)-$(BUILD_SUBPLATFORM)
endif

config:
	$(MAKE) $(CONFIG_TARGET)

.PHONY: config

################################################################
# Compile
################################################################

# Buildbot must set the variables PLATFORM and SUBPLATFORM

ifeq ($(BUILD_SUBPLATFORM),)
COMPILE_TARGET = compile-$(BUILD_PLATFORM)
else
COMPILE_TARGET = compile-$(BUILD_PLATFORM)-$(BUILD_SUBPLATFORM)
endif

compile:
	$(MAKE) $(COMPILE_TARGET)

.PHONY: compile

################################################################
# Archive / extract built binaries
################################################################

bin-archive:
	tar -Jcvf $(BUILD_PLATFORM)-bin.tar.xz $(BUILD_PLATFORM)-bin

bin-extract:
	find . -maxdepth 1 -name '*-bin.tar.xz' -print0 | xargs -0 -n1 tar -xvf

################################################################
# Installer generation
################################################################

# BUILD_PLATFORM will be set to the platform on which the installer's being
# built.  Its build artefacts will have been extracted into the
# ./$(BUILD_PLATFORM)-bin/ directory

# FIXME at the moment we only generate community edition installers

BUILD_STABILITY ?= beta
BUILD_EDITION ?= community

BUILDTOOL_STACK = builder/builder_tool.livecodescript

WKHTMLTOPDF ?= $(shell which wkhtmltopdf 2>/dev/null)

bin_dir = $(BUILD_PLATFORM)-bin

ifeq ($(BUILD_PLATFORM),mac)
  LIVECODE = $(bin_dir)/LiveCode-Community.app/Contents/MacOS/LiveCode-Community
  buildtool_platform = mac
else ifeq ($(BUILD_PLATFORM),linux-x86)
  LIVECODE = $(bin_dir)/livecode-community
  buildtool_platform = linux
endif

# FIXME add --warn-as-error
buildtool_command = $(LIVECODE) -ui $(BUILDTOOL_STACK) \
	--edition $(BUILD_EDITION) --build $(BUILD_STABILITY) \
	--engine-dir . --output-dir . --work-dir ./_cache/builder_tool \
	--private-dir ..

dist-docs:
	$(buildtool_command) --platform $(buildtool_platform) --stage docs

dist-notes:
	WKHTMLTOPDF=$(WKHTMLTOPDF) \
	$(buildtool_command) --platform $(buildtool_platform) --stage notes

dist-server:
	$(buildtool_command) --platform mac --platform win --platform linux \
	    --stage server

# FIXME temporarily building installers only for Linux!
dist-tools:
	$(buildtool_command) --platform linux \
	    --stage tools
