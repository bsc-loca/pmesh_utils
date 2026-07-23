<div align="center">

# pmesh_utils

</div>

This repository contains pmesh (OpenPiton) utility modules.

Each utility modules are placed under separate subdirectory.

axi_to_pmesh_bridge :
- converts peripheral AXI transactions into NoC packets.
- more details about the micro-acrhitecture and running tests can be found at its README.

pmesh_width_adapter : 
- acts as an adapter while connecting pmesh NoC Channels of different widths.
- requires openpiton generated file - define.tmp.h
