SHELL := /bin/bash

# Top level
export ROOT_DIR := $(shell pwd)

# RTL Top File
export RTL_TOP := axi_to_pmesh_bridge

# Filelist for linting
export LINT_FILELIST := $(ROOT_DIR)/lint_filelist.f

# VC spyglass report directory
export REPORTS_DIR       = Reports
export REPORTS_DIR_PATH  = $(ROOT_DIR)

# Linting: VC spyglass RTL lint
vc_lint_check:
	@mkdir -p $(REPORTS_DIR_PATH)/$(REPORTS_DIR)
	@vc_static_shell -f scripts/lint_vc_spyglass.tcl -batch

# clean lint Reports
clean:
	@rm -rf Reports/ WORK/ .vcstPref vcst_rtdb *.log *.bak .dw_map_file