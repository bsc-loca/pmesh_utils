###############################################################################
# VC Spyglass Lint script
# Version: 1
# Created on: 01 Dec 2025
# Created by: Manjunath - manjunath.kalmath@bsc.es
###############################################################################

#Get the required variables from the Makefile
set ROOT_DIR            $env(ROOT_DIR)
set RTL_TOP             $env(RTL_TOP)
set LINT_FILELIST       $env(LINT_FILELIST)
set REPORTS_DIR         $env(REPORTS_DIR)
set REPORTS_DIR_PATH    $env(REPORTS_DIR_PATH)

#Settings to enable VC SpyGlass LINT flow
set_app_var enable_lint true

#Goal Configuration
configure_lint_setup -goal lint_rtl

set_app_var search_path "$ROOT_DIR/include/"

#Waivers:
source scripts/axi_to_pmesh_bridge_lint_waiver.tcl

#Load Design
define_design_lib WORK -path WORK/VCS
analyze -format sverilog -vcs {-f $LINT_FILELIST}
elaborate $RTL_TOP

#Command to check LINT
check_lint

#The following command generates a verbose report
report_violations -app {lint} -verbose -limit 0 -file $REPORTS_DIR_PATH/$REPORTS_DIR/vc_spyglass_lint.rpt
