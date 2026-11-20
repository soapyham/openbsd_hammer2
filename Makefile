SUBDIRS = src

.PHONY: all clean $(SUBDIRS)

all: $(SUBDIRS)
$(SUBDIRS):
	$(MAKE) -C $@
clean:
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir $@; \
	done
install:
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/install.sh; else doas ksh -x ./script/install.sh; fi
uninstall:
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/uninstall.sh; else doas ksh -x ./script/uninstall.sh; fi
prep:
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/prep.sh; else doas ksh -x ./script/prep.sh; fi
unprep:
	@if [ "$$(id -u)" -eq 0 ]; then ksh -x ./script/unprep.sh; else doas ksh -x ./script/unprep.sh; fi
