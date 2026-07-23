# Organization   : Barcelona Supercomputing Center
# File           : noc_width_test.py
# Description    : This python file runs the cocotb tests with all
#                  possible openpiton noc widths
# ------------------------------------------------------------------
# COPYRIGHT
#  Copyright (c) Barcelona Supercomputing Center, 2024-2025.
# ------------------------------------------------------------------
# LICENSE
#  Licensed under the Solderpad Hardware License v 2.1 (the
#  "License"); you may not use this file except in compliance
#  with the License, or, at your option, the Apache License
#  version 2.0. You may obtain a copy of the License at
#
#  http://www.solderpad.org/licenses/SHL-2.1
#
#  Unless required by applicable law or agreed to in writing,
#  work distributed under the License is distributed on an
#  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
#  either express or implied. See the License for the specific
#  language governing permissions and limitations under the License.
# ------------------------------------------------------------------
# Revision History
#  Revision   | Author                                 | Description
#  0.0.1      | lap - luis.plana@bsc.es                | initial code version
#             | Manjunath - manjunath.kalmath@bsc.es   | initial code version
# ------------------------------------------------------------------

import re
import logging
import argparse
import subprocess
from pathlib import Path

# code for printing in colored text
GREEN  = "\033[92m"
RED    = "\033[91m"
RESET  = "\033[0m"

# argument parser
parser = argparse.ArgumentParser(description="python noc width test")
parser.add_argument("--sim", type=str, choices=["questa", "vcs", "verilator"], default="verilator", help="simulator name to run cocotb test")
args = parser.parse_args()

# logging setup
logging.basicConfig(
    level=logging.DEBUG,
    format="%(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("noc_width_test_results.log", mode="w")
    ]
)

logger = logging.getLogger(__name__)

# function to modify the content of file - define.tmp.h
# modify the piton noc widths
def modify_file_content(path, content, piton_noc, width):
    content = re.sub(rf"(`define {piton_noc})\s+\d+", rf"\1 {width}", content)
    logger.info(f"`define {piton_noc} {width}")
    return content

# function to run cocotb tests and print the tests status
# run cocotb tests on modified file - define.tmp.h
def run_tests(path, content):
    # construct the loop to run the tests
    # note. noc_axi4_bridge_deser has no support to handle other than these noc2 width
    noc_2_width = [64, 128, 192, 256, 320, 704]
    count = 0
    test_flag = 0
    for i in range(64, 705, 64):
        for j in noc_2_width:
            for k in range(64, 705, 64):
                count += 1
                new_noc_widths = {
                    "PITON_NOC1_WIDTH": i,
                    "PITON_NOC2_WIDTH": j,
                    "PITON_NOC3_WIDTH": k
                }
                logger.info(f"""
                    ****************************************************************************
                    **Running test {count}/726 for the following PITON_NOC_WIDTH configuration**
                    ****************************************************************************
                """)
                for piton_noc, width in new_noc_widths.items():
                    content = modify_file_content(path, content, piton_noc, width)
                path.write_text(content)
                logger.info("Modified the file --> define.tmp.h")
                logger.info("Running cocotb tests")
                sim_result = subprocess.run(["make", "clean"], capture_output=True, text=True)
                sim_result = subprocess.run(["make", f"SIM={args.sim}", "WAVES=0"], capture_output=True, text=True)
                lines = sim_result.stdout.splitlines()
                if args.sim == "vcs":
                    result_lines = lines[-17:-6]
                elif args.sim == "questa":
                    result_lines = lines[-16:-6]
                else:
                    result_lines = lines[-13:-2]
                for line in result_lines:
                    logger.info(f"{line}")
                result_text  = "\n".join(result_lines)
                if "TESTS=4" in result_text and "PASS=4" in result_text and "FAIL=0" in result_text:
                    logger.info(f"All tests {GREEN} passed{RESET}!")
                    test_flag += 1
                else:
                    logger.error(f"Test {RED} Failed{RESET}!")
                logger.info("------------------------------------------------------------------\n")

    # final status about the noc_width_test
    if test_flag == 726:
        logger.info(f"{GREEN}noc_width_test passed!{RESET}")
    else:
        logger.error(f"{RED}noc_width_test failed!{RESET}")

# function to revert back the piton_noc_widths to the BSC configuration
def revert_piton_noc_config(path, content):
    new_noc_widths = {
        "PITON_NOC1_WIDTH": 256,
        "PITON_NOC2_WIDTH": 704,
        "PITON_NOC3_WIDTH": 704
        }
    for piton_noc, width in new_noc_widths.items():
        content = modify_file_content(path, content, piton_noc, width)
    path.write_text(content)
    logger.info("Modified the file --> define.tmp.h")
    logger.info("Reverted back the piton_noc_widths to the BSC configuration")

# main function
def main():
    # find the file - define.tmp.h
    file_path = Path.cwd().parent/"include"/"define.tmp.h"

    try:
        file_content = file_path.read_text()

    except FileNotFoundError:
        print(f"Error: Could not find the file at {file_path}")
        return

    try:
        run_tests(file_path, file_content)

    except KeyboardInterrupt:
        print("COCOTB Test interrupted\n")

    finally:
        revert_piton_noc_config(file_path, file_content)

if __name__ == "__main__":
    main()
