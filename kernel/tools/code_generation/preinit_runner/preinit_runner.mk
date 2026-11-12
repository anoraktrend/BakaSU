# preinit runner: a static nolibc binary embedded into kernelsu, see preinit/.
# It is built against the installed UAPI headers of the target kernel
# (CONFIG_HEADERS_INSTALL, enabled by gki_defconfig).
# $(objtree) is "." whenever kbuild runs with the object tree as the working
# directory (after the top-level O= split) and unset in a few other
# invocations. Resolve it once, preferring the explicit O= and falling back to
# the working directory, so the header check, the fallback install and the
# runner build all agree on one absolute tree.
KSU_OBJTREE := $(abspath $(if $(filter-out . ./,$(objtree)),$(objtree),$(if $(O),$(O),$(CURDIR))))
KSU_UAPI_INC := $(KSU_OBJTREE)/usr/include

ifeq ($(wildcard $(KSU_UAPI_INC)/linux/unistd.h),)
# Fallback for trees that do not install the UAPI headers themselves. Run the
# nested make from the object tree, the way kbuild's own split sub-make does:
# with KBUILD_SRC set the top-level Makefile resolves every relative generated
# path against the working directory, so a child that is pointed at the source
# tree (make -C $(srctree), as this used to) writes its generated headers into
# the sources. That dies with EROFS on read-only trees such as Android's build
# sandbox, and on writable trees it silently pollutes the sources; with the
# working directory on the object tree everything lands where it belongs.
KSU_HEADERS_INSTALL_OUTPUT := $(shell mkdir -p "$(KSU_OBJTREE)" && cd "$(KSU_OBJTREE)" && \
	$(MAKE) -s -f "$(abspath $(srctree))/Makefile" \
	--include-dir="$(abspath $(srctree))" \
	KBUILD_SRC="$(abspath $(srctree))" \
	ARCH="$(ARCH)" headers_install INSTALL_HDR_PATH="$(KSU_OBJTREE)/usr")
endif

ifeq ($(wildcard $(KSU_UAPI_INC)/linux/unistd.h),)
$(error $(REPO_NAME): the preinit runner needs the kernel UAPI headers, but $(KSU_UAPI_INC)/linux/unistd.h is missing and installing it failed. Install them with "make O=$(KSU_OBJTREE) headers_install" (or make the object tree writable) and rebuild.)
endif

kernelsu-objs += preinit/preinit.o
kernelsu-objs += preinit/blob.o

KSU_RUNNER_OBJ := $(abspath $(obj))
KSU_RUNNER_BIN := $(KSU_RUNNER_OBJ)/preinit/runner.elf
KSU_RUNNER_TARGET := $(obj)/preinit/runner.elf
KSU_RUNNER_SRC := $(KSU_SRC)/preinit/runner

KSU_RUNNER_CFLAGS := $(CLANG_FLAGS) -std=gnu11 -Os -Wall \
	-nostdinc -isystem $(shell $(CC) -print-file-name=include) \
	-I$(KSU_RUNNER_SRC)/nolibc -I$(KSU_UAPI_INC) \
	-I$(KSU_SRC)/include \
	-ffreestanding -fno-stack-protector -fno-pic -fno-pie \
	-fno-asynchronous-unwind-tables -fno-unwind-tables \
	-ffunction-sections -fdata-sections

KSU_RUNNER_LIBS :=
ifeq ($(ARCH),arm)
KSU_RUNNER_LIBS := $(shell $(CC) $(CLANG_FLAGS) -print-libgcc-file-name)
endif

quiet_cmd_ksu_runner = CC      $@
      cmd_ksu_runner = mkdir -p $(dir $@) && \
		$(CC) $(KSU_RUNNER_CFLAGS) -c -o $@.o $< && \
		$(LD) -static -nostdlib -e _start --gc-sections -s -o $@ $@.o $(KSU_RUNNER_LIBS) && \
		rm -f $@.o

$(KSU_RUNNER_TARGET): $(KSU_RUNNER_SRC)/runner.c \
		$(wildcard $(KSU_RUNNER_SRC)/nolibc/*.h \
			   $(KSU_RUNNER_SRC)/nolibc/sys/*.h \
			   $(KSU_SRC)/include/uapi/*.h) FORCE
	$(call if_changed,ksu_runner)

targets += preinit/runner.elf
$(obj)/preinit/blob.o: $(KSU_RUNNER_TARGET)
asflags-y += -DKSU_PREINIT_RUNNER_BIN=\"$(KSU_RUNNER_BIN)\"

