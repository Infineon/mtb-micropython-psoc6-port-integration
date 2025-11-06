MTB_LIBS_DIR ?= $(TOP)/lib/mtb-psoc6-libs

# This file is used to track the current active bsp in 
# the ModusToolbox library project.
# This prevents the need to specify BOARD=XXX
# variable for every call to make in the micropython build. 
# Instead, it only needs to be specified for the first build:
# $ make BOARD=CY8CKIT-062S2-AI //first time build
# $ make 						//subsequent builds (without BOARD variable)
MTB_ACTIVE_BSP_FILE = $(MTB_LIBS_DIR)/.mtb_active_bsp

# Check if the active BSP file exists and read its content
ifneq ($(wildcard $(MTB_ACTIVE_BSP_FILE)),)
    ACTIVE_BOARD := $(shell cat $(MTB_ACTIVE_BSP_FILE) 2>/dev/null | head -1)
else
    ACTIVE_BOARD :=
    $(info No active BSP file found)
endif

# Use active board if no BOARD is specified.
ifeq ($(BOARD),)
    ifneq ($(ACTIVE_BOARD),)
        BOARD := $(ACTIVE_BOARD)
        $(info Using active board: $(BOARD))
    endif
endif

BOARD_DIR  = boards/$(BOARD)
ifeq ($(wildcard $(BOARD_DIR)/.),)
   $(error Invalid BOARD specified)
endif

# If the board is different than the active one, remove the active BSP file.
# The mtb_init target needs to be run again to re-initialize the MTB libraries.
ifneq ($(BOARD),$(ACTIVE_BOARD))
   $(info Board changed from '$(ACTIVE_BOARD)' to '$(BOARD)'. Re-initializing ModusToolbox libraries.)
   $(shell rm -f $(MTB_ACTIVE_BSP_FILE))
endif

-include $(BOARD_DIR)/mpconfigboard.mk

.PHONY: mtb_ble_gen
mtb_ble_gen:
ifeq ($(MICROPY_PY_BLUETOOTH),1)
	$(Q) cp $(MTB_LIBS_DIR)/ble/design.cybt $(MTB_LIBS_DIR)
else
@:
endif

mtb_init: $(MTB_ACTIVE_BSP_FILE) 

$(MTB_ACTIVE_BSP_FILE):
	$(info )
	$(MAKE) mtb_bsp_init
	$(info Creating active BSP file: $@)
	$(Q) echo $(BOARD) >> $@
	$(info Initialized ModusToolbox libs for board $(BOARD))

# Added as separate target to ensure it is only run when 
# the .mtb_active_bsp file does not exist
mtb_bsp_init: mtb_deinit mtb_ble_gen mtb_add_bsp mtb_set_bsp mtb_get_libs

# The ModusToolbox expects all the .mtb files to be in the /deps folder.
# The feature specific dependencies organized in folders are directly copied 
# to the deps/ root folder
# In theory, the build inclusion/exclusion of components can be handled by the 
# COMPONENTS variable of the ModusToolbox Makefile. T
# This feature does not seem to scale well for this use case (Or better knowledge
# on how to use it is required :|).
# It seems easier to just explicitly include only those middleware assets 
# and libraries required for a given bsp and its required MicroPython capabilities.

MTB_DEPS_DIRS = common
ifeq ($(MICROPY_PY_NETWORK),1)
MTB_DEPS_DIRS += network
endif

ifeq ($(MICROPY_PY_EXT_FLASH),1)
MTB_DEPS_DIRS += ext_flash
endif

ifeq ($(MICROPY_PY_SSL), 1)
MTB_DEPS_DIRS += crypto
endif

ifeq ($(MICROPY_PY_BLUETOOTH), 1)
MTB_DEPS_DIRS += ble
endif

mtb_config_deps: 
	@:
	$(info )
	$(info Configuring ModusToolbox dependencies ...)
	$(info mtb_deps_dir  : $(MTB_LIBS_DIR)/deps/$(MTB_DEPS_DIRS)/)
	$(Q) $(foreach DIR, $(MTB_DEPS_DIRS), $(shell cp -r $(MTB_LIBS_DIR)/deps/$(DIR)/. $(MTB_LIBS_DIR)/deps))
	$(info mtb_bsp_deps_dir : Updating dependencies for $(BOARD) ...)
	$(Q) bash $(MTB_LIBS_DIR)/mtb_bsp_set_deps_ver.sh $(BOARD)

mtb_get_libs: mtb_config_deps
	$(info )
	$(info Retrieving ModusToolbox dependencies ...)
	$(Q) $(MAKE) -C $(MTB_LIBS_DIR) getlibs

mtb_add_bsp:
	$(info )
	$(info Adding board $(BOARD) dependencies ...)
	$(Q) cd $(MTB_LIBS_DIR); library-manager-cli --project . --add-bsp-name $(BOARD) --add-bsp-version $(BOARD_VERSION)

mtb_set_bsp: 
	$(info )
	$(info Setting board $(BOARD) as active ...)
	$(Q) cd $(MTB_LIBS_DIR); library-manager-cli --project . --set-active-bsp APP_$(BOARD)

mtb_deinit: mtb_clean
	$(info )
	$(info Removing mtb_shared, bsps, libs dirs, and metafiles...)
	-$(Q) cd $(MTB_LIBS_DIR); rm -rf bsps
	-$(Q) cd $(MTB_LIBS_DIR); rm -rf libs
	-$(Q) cd $(MTB_LIBS_DIR); rm -rf ../mtb_shared
	-$(Q) cd $(MTB_LIBS_DIR); find deps/*.mtb -maxdepth 1 -type f -delete
	-$(Q) rm -rf $(MTB_LIBS_BUILD_DIR)
	-$(Q)rm -rf $(MTB_LIBS_DIR)/GeneratedSource/
	-$(Q)rm -f $(MTB_LIBS_DIR)/design.cybt
	-$(Q) rm -f $(MTB_ACTIVE_BSP_FILE)

mtb_bsp_help:
	@:
	$(info )
	$(info ModusToolbox BSP setup available targets:)
	$(info )
	$(info 	mtb_init            Initialize ModusToolbox libraries for the selected board.)
	$(info  ..                  It depends on mtb_deinit, mtb_add_bsp, mtb_set_bsp and mtb_get_libs)
	$(info  mtb_add_bsp         Add the selected board BSP to the project)
	$(info  mtb_set_bsp         Set the selected board as active)
	$(info  mtb_get_libs        Download ModusToolbox libraries and dependencies)
	$(info	mtb_deinit          Remove ModusToolbox libraries and dependencies)
	$(info 	mtb_bsp_help        Show this help message)
	$(info )

.PHONY: mtb_deinit mtb_add_bsp mtb_set_bsp mtb_get_libs mtb_bsp_help