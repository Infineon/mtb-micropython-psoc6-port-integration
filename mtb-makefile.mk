MTB_LIBS_DIR ?= ../../lib/mtb-psoc6-libs
MTB_MAKEFILE := $(MTB_LIBS_DIR)/Makefile

ifeq ($(CONFIG),)
CONFIG = $(shell egrep '^ *CONFIG' $(MTB_MAKEFILE) | sed 's/^.*= *//g')
$(info Using CONFIG from environment: $(CONFIG))
endif

MTB_LIBS_BUILD_DIR       := $(MTB_LIBS_DIR)/build
MTB_LIBS_BOARD_BUILD_DIR := $(MTB_LIBS_BUILD_DIR)/APP_$(BOARD)/$(CONFIG)

MTB_STATIC_LIB_NAME		 = $(shell egrep '^ *LIBNAME' $(MTB_MAKEFILE) | sed 's/^.*= *//g')
MTB_BUILD_METAFILES_NAME = inclist.rsp liblist.rsp artifact.rsp .cycompiler .cylinker $(MTB_STATIC_LIB_NAME).a
MTB_BUILD_METAFILES      = $(addprefix $(MTB_LIBS_BOARD_BUILD_DIR)/,$(MTB_BUILD_METAFILES_NAME))

MPY_MTB_MAKE_VARS = MICROPY_PY_NETWORK=$(MICROPY_PY_NETWORK) MICROPY_PY_SSL=$(MICROPY_PY_SSL) BOARD=$(BOARD) CONFIG=$(CONFIG)

$(MTB_BUILD_METAFILES):
	$(info )
	$(info Building $(BOARD) in $(CONFIG) mode using MTB ...)
	$(Q) $(MAKE) -C $(MTB_LIBS_DIR) $(MPY_MTB_MAKE_VARS) build

mtb_build: $(MTB_BUILD_METAFILES)

mtb_get_build_flags: mtb_build
	$(eval MPY_MTB_INCLUDE_DIRS = $(file < $(MTB_LIBS_BOARD_BUILD_DIR)/inclist.rsp))
	$(eval INC                 += $(subst -I,-I$(MTB_LIBS_DIR)/,$(MPY_MTB_INCLUDE_DIRS)))
	$(eval INC                 += -I$(BOARD_DIR))
	$(eval MPY_MTB_LIBRARIES    = $(file < $(MTB_LIBS_BOARD_BUILD_DIR)/liblist.rsp))
	$(eval LIBS                += $(MTB_LIBS_BOARD_BUILD_DIR)/$(MTB_STATIC_LIB_NAME).a)
	$(eval CFLAGS              += $(shell $(PYTHON) $(MTB_LIBS_DIR)/mtb_build_info.py ccxxflags $(MTB_LIBS_BOARD_BUILD_DIR)/.cycompiler ))
	$(eval CXXFLAGS            += $(CFLAGS))
	$(eval LDFLAGS             += $(shell $(PYTHON) $(MTB_LIBS_DIR)/mtb_build_info.py ldflags $(MTB_LIBS_BOARD_BUILD_DIR)/.cylinker $(MTB_LIBS_DIR)))
	$(eval QSTR_GEN_CFLAGS     += $(INC) $(CFLAGS))

mtb_clean:
	$(info )
	$(info Cleaning MTB build projects)
	-$(Q) $(MAKE) -C $(MTB_LIBS_DIR) clean
	-$ rm -rf $(MTB_LIBS_BUILD_DIR)

# When multiple types of boards are connected, a devs file needs to be provided.
# When working locally, if a "local-devs.yml" file is placed in "tools/psoc6"
# it will be used
ifneq ($(DEVS_FILE),)
MULTI_BOARD_DEVS_OPTS = -b $(BOARD) -y $(DEVS_FILE)
else 
DFLT_LOCAL_DEVS_FILE_NAME = local-devs.yml
LOCAL_DEVS_FILE=$(TOP)/tools/psoc6/$(DFLT_LOCAL_DEVS_FILE_NAME)
ifneq (,$(wildcard $(LOCAL_DEVS_FILE)))
MULTI_BOARD_DEVS_OPTS = -b $(BOARD) -y $(LOCAL_DEVS_FILE)
endif
endif

attached_devs:
	@:
	$(eval ATTACHED_TARGET_LIST = $(shell $(PYTHON) $(TOP)/tools/psoc6/get_devs.py serial-number $(MULTI_BOARD_DEVS_OPTS)))
	$(eval ATTACHED_TARGETS_NUMBER = $(words $(ATTACHED_TARGET_LIST)))
	$(info Number of attached targets : $(ATTACHED_TARGETS_NUMBER))
	$(info List of attached targets : $(ATTACHED_TARGET_LIST))

ifndef EXT_HEX_FILE
HEX_FILE = $(BUILD)/firmware.hex
PROG_DEPS=$(BUILD)
else
HEX_FILE = $(EXT_HEX_FILE)
endif

MTB_HOME     ?= $(HOME)/ModusToolbox
OPENOCD_HOME ?= $(MTB_HOME)/tools_3.0/openocd

# Selection of openocd cfg files based on board
OPENOCD_CFG_SEARCH = $(MTB_LIBS_DIR)/bsps/TARGET_APP_$(BOARD)/config/GeneratedSource

mtb_program: $(PROG_DEPS)
	@:
	$(info )
	$(info Programming using openocd ...)
	openocd -s $(OPENOCD_HOME)/scripts -s $(OPENOCD_CFG_SEARCH) -c "source [find interface/kitprog3.cfg]; $(SERIAL_ADAPTER_CMD) ; source [find target/$(OPENOCD_TARGET_CFG)]; psoc6 allow_efuse_program off; psoc6 sflash_restrictions 1; program $(HEX_FILE) verify reset exit;"
	$(info Programming done.)

mtb_program_multi: attached_devs
	@:
	$(foreach ATTACHED_TARGET, $(ATTACHED_TARGET_LIST), $(MAKE) qdeploy SERIAL_ADAPTER_CMD='adapter serial $(ATTACHED_TARGET)';)

mtb_build_help:
	@:
	$(info )
	$(info ModusToolbox build available targets:)
	$(info )
	$(info 	mtb_build               Build the mtb psoc6 lib project)
	$(info  mtb_get_build_flags     Retrieve build flags for mtb psoc6 lib build)
	$(info 	mtb_program             Program the built firmware to the connected board.)
	$(info 	mtb_program_multi       Program multiple connected boards of the same type.)
	$(info  Options: )
	$(info  - EXT_HEX_FILE          An external .hex file can be provided to the program )
	$(info  ..                      targets, instead of building from the sources.)
	$(info 	mtb_clean               Clean the ModusToolbox build files)
	$(info 	mtb_build_help          Show this help message)
	$(info )

.PHONY: mtb_build mtb_get_build_flags mtb_program mtb_program_multi attached_devs mtb_clean mtb_build_help