#!/usr/local/bin/perl -wpi.bak

s/ossv_magic/ossv_bridge/g;
s/NEW_MAGIC/NEW_BRIDGE/g;
s/sv_2magic/sv_2bridge/g;
s/force_sv_2magic/force_sv_2bridge/g;
s/_magic/_bridge/g;
