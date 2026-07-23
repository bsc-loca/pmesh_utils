# Lint Filelist

# Openpiton Header files
+incdir+${ROOT_DIR}/example/openpiton/include/

# Package file
${ROOT_DIR}/include/axi_to_pmesh_bridge_pkg.sv

# RTL files
${ROOT_DIR}/src/addr_to_x_y.sv
${ROOT_DIR}/src/axi_slave_rd_pipeline.sv
${ROOT_DIR}/src/axi_slave_wrapper_pipeline.sv
${ROOT_DIR}/src/axi_slave_wr_pipeline.sv
${ROOT_DIR}/src/axi_to_pmesh_bridge.sv
${ROOT_DIR}/src/fifo_v3.sv
${ROOT_DIR}/src/noc_driver.sv
${ROOT_DIR}/src/noc_requests.sv
${ROOT_DIR}/src/noc_responses.sv
${ROOT_DIR}/src/alexforencich_priority_encoder.v
${ROOT_DIR}/src/transfer_unroller.sv
${ROOT_DIR}/src/write_unroller.sv

# Additional RTL files - python generated files in Openpiton platform
${ROOT_DIR}/example/openpiton/src/l15_home_encoder.tmp.v
${ROOT_DIR}/example/openpiton/src/flat_id_to_xy.tmp.v
