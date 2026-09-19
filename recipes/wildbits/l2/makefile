LEVEL = 2
SCF_EXTRA = SOLdrv fSOL wizfi wz wz0 wz1 wz2 wz3 vt vt1 vt2 vt3 vt4 vt5 vt6 vt7 vt8
CMDS_EXTRA = grfdrv256 wsigtst vs ssbench joyview
include ../wildbits.mak

# vtio and grfdrv256 are driven almost entirely by defs/wildbits_vtio.d - the
# TermSave* switches, the GF.* op numbers, the V.* static layout and the T.*
# buffer layout all live there - but no rule in wildbits.mak lists a defs file
# as a prerequisite, so editing one silently leaves a stale module behind.  That
# already cost a hardware round trip: a TermSave* change appeared to build and
# the .mods file was untouched.  (Same class as krn not depending on flink.asm.)
$(MODDIR)/vtio $(MODDIR)/grfdrv256 $(MODDIR)/vtcmd $(MODDIR)/$(KEYSUB) $(MODDIR)/wsigtst $(MODDIR)/ssbench $(MODDIR)/joyview: $(DEFSDIR)/wildbits_vtio.d $(DEFSDIR)/wildbits.d

# wsigtst exercises SS.WSig ($E1); it lives with the other level 2 wildbits
# commands, which have no generic rule here.
$(MODDIR)/wsigtst: $(LEVEL2)/wildbits/cmds/wsigtst.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@

# ssbench times the calls Joust makes every frame (joust docs/driver-work.md).
$(MODDIR)/ssbench: $(LEVEL2)/wildbits/cmds/ssbench.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@

# joyview shows what SS.Joy returns for both sticks and four NES/SNES pads.
$(MODDIR)/joyview: $(LEVEL2)/wildbits/cmds/joyview.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@

# vs - Roger Taylor's VS1053 tool (edition 13): the only instrument that exercises
# the chip on its own, independently of Joust and of the codec settings.  vs -i shows
# the GPIO straps and every SCI register, vs -t runs the SDI and SCI sine tests, and
# vs -s <file> plays an MP3/OGG/WAV.  It carries the switcher plug-in in its own
# Switch table, so it needs nothing from SYS/VSPLUGINS.  Added 2026-09-18 while
# chasing Jr2 silence; it lives in level1 and has no generic rule here.
$(MODDIR)/vs: $(LEVEL1)/wildbits/cmds/vs.asm | $(MODDIR)
	$(AS) $(AFLAGS) $< $(ASOUT)$@
