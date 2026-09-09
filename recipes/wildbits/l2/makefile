LEVEL = 2
SCF_EXTRA = SOLdrv fSOL wizfi wz wz0 wz1 wz2 wz3 vt vt1 vt2 vt3 vt4 vt5 vt6 vt7 vt8
CMDS_EXTRA = grfdrv256
include ../wildbits.mak

# vtio and grfdrv256 are driven almost entirely by defs/wildbits_vtio.d - the
# TermSave* switches, the GF.* op numbers, the V.* static layout and the T.*
# buffer layout all live there - but no rule in wildbits.mak lists a defs file
# as a prerequisite, so editing one silently leaves a stale module behind.  That
# already cost a hardware round trip: a TermSave* change appeared to build and
# the .mods file was untouched.  (Same class as krn not depending on flink.asm.)
$(MODDIR)/vtio $(MODDIR)/grfdrv256: $(DEFSDIR)/wildbits_vtio.d $(DEFSDIR)/wildbits.d
