################################################################################
# Following variables defines how the NS_USER (Non Secure User - Client
# Application), NS_KERNEL (Non Secure Kernel), S_KERNEL (Secure Kernel) and
# S_USER (Secure User - TA) are compiled
################################################################################
override COMPILE_NS_USER   := 32
override COMPILE_NS_KERNEL := 32
override COMPILE_S_USER    := 32
override COMPILE_S_KERNEL  := 32

include common.mk

################################################################################
# Paths to git projects and various binaries
################################################################################
BIOS_QEMU_PATH			?= $(ROOT)/bios_qemu_tz_arm
QEMU_PATH			?= $(ROOT)/qemu
BINARIES_PATH			?= $(ROOT)/out/bin
ARM_TF_PATH			?= $(ROOT)/arm-trusted-firmware
SOC_TERM_PATH			?= $(ROOT)/soc_term

DEBUG = 1

################################################################################
# Targets
################################################################################
ifeq ($(CFG_TEE_BENCHMARK),y)
all: benchmark-app
clean: benchmark-app-clean
endif
all: bios-qemu qemu soc-term optee-examples
clean: bios-qemu-clean busybox-clean linux-clean optee-os-clean \
	optee-client-clean qemu-clean soc-term-clean check-clean \
	optee-examples-clean

include toolchain.mk

################################################################################
# QEMU
################################################################################
define bios-qemu-common
	+$(MAKE) -C $(BIOS_QEMU_PATH) \
		CROSS_COMPILE=$(CROSS_COMPILE_NS_USER) \
		O=$(ROOT)/out/bios-qemu \
		PLATFORM_FLAVOR=virt
endef

bios-qemu: update_rootfs optee-os
	mkdir -p $(BINARIES_PATH)
	ln -sf $(OPTEE_OS_HEADER_V2_BIN) $(BINARIES_PATH)
	ln -sf $(OPTEE_OS_PAGER_V2_BIN) $(BINARIES_PATH)
	ln -sf $(OPTEE_OS_PAGEABLE_V2_BIN) $(BINARIES_PATH)
	ln -sf $(LINUX_PATH)/arch/arm/boot/zImage $(BINARIES_PATH)
	ln -sf $(GEN_ROOTFS_PATH)/filesystem.cpio.gz \
		$(BINARIES_PATH)/rootfs.cpio.gz
	$(call bios-qemu-common)

bios-qemu-clean:
	$(call bios-qemu-common) clean

qemu:
	cd $(QEMU_PATH); ./configure --target-list=arm-softmmu\
			$(QEMU_CONFIGURE_PARAMS_COMMON)
	$(MAKE) -C $(QEMU_PATH)

qemu-clean:
	$(MAKE) -C $(QEMU_PATH) distclean

################################################################################
# ARM Trusted Firmware
################################################################################
ARM_TF_EXPORTS ?= \
	CFLAGS="-O0 -gdwarf-2" \
	CROSS_COMPILE="$(CCACHE)$(AARCH32_CROSS_COMPILE)"

ARM_TF_DEBUG ?= 0

ARM_TF_FLAGS ?= \
	ARM_ARCH_MAJOR=7 \
	ARCH=aarch32 \
	PLAT=qemu \
	DEBUG=$(ARM_TF_DEBUG) \
	LOG_LEVEL=60 \
	ERROR_DEPRECATED=1 \
	ARM_TSP_RAM_LOCATION=tdram \
	BL32_RAM_LOCATION=tdram \
	BL33=$(ROOT)/out/bios-qemu/bios.bin \
	AARCH32_SP=optee \
	BL32=$(OPTEE_OS_HEADER_V2_BIN) \
	BL32_EXTRA1=$(OPTEE_OS_PAGER_V2_BIN) \
	BL32_EXTRA2=$(OPTEE_OS_PAGEABLE_V2_BIN)

# This is where ATF generates the firmware binaries
ifeq ($(ARM_TF_DEBUG),0)
ARM_TF_OUT = $(ARM_TF_PATH)/build/qemu/release
else
ARM_TF_OUT = $(ARM_TF_PATH)/build/qemu/debug
endif

arm-tf: optee-os linux
	$(ARM_TF_EXPORTS) $(MAKE) -C $(ARM_TF_PATH) $(ARM_TF_FLAGS) all fip

arm-tf-clean:
	$(ARM_TF_EXPORTS) $(MAKE) -C $(ARM_TF_PATH) $(ARM_TF_FLAGS) clean

################################################################################
# Busybox
################################################################################
BUSYBOX_COMMON_TARGET = vexpress
BUSYBOX_CLEAN_COMMON_TARGET = vexpress clean

busybox: busybox-common

busybox-clean: busybox-clean-common

busybox-cleaner: busybox-cleaner-common

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH := arm
LINUX_DEFCONFIG_COMMON_FILES := \
		$(LINUX_PATH)/arch/arm/configs/vexpress_defconfig \
		$(CURDIR)/kconfigs/qemu.conf

linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=arm

linux: linux-common

linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=arm

linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=arm

linux-cleaner: linux-cleaner-common

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS += PLATFORM=vexpress-qemu_virt
optee-os: optee-os-common

OPTEE_OS_CLEAN_COMMON_FLAGS += PLATFORM=vexpress-qemu_virt
optee-os-clean: optee-os-clean-common

optee-client: optee-client-common

optee-client-clean: optee-client-clean-common

################################################################################
# Soc-term
################################################################################
soc-term:
	$(MAKE) -C $(SOC_TERM_PATH)

soc-term-clean:
	$(MAKE) -C $(SOC_TERM_PATH) clean

################################################################################
# xtest / optee_test
################################################################################
xtest: xtest-common

xtest-clean: xtest-clean-common

xtest-patch: xtest-patch-common

################################################################################
# Sample applications / optee_examples
################################################################################
optee-examples: optee-examples-common

optee-examples-clean: optee-examples-clean-common

################################################################################
# benchmark
################################################################################
benchmark-app: benchmark-app-common

benchmark-app-clean: benchmark-app-clean-common

################################################################################
# Root FS
################################################################################
filelist-tee: filelist-tee-common

update_rootfs: update_rootfs-common

################################################################################
# Run targets
################################################################################
.PHONY: run
# This target enforces updating root fs etc
run: all
	$(MAKE) run-only

.PHONY: run-only
run-only:
	$(call check-terminal)
	$(call run-help)
	$(call launch-terminal,54320,"Normal World")
	$(call launch-terminal,54321,"Secure World")
	$(call wait-for-ports,54320,54321)
	(cd $(BINARIES_PATH) && $(QEMU_PATH)/arm-softmmu/qemu-system-arm \
		-nographic \
		-serial tcp:localhost:54320 -serial tcp:localhost:54321 \
		-s -S -machine virt -machine secure=on -cpu cortex-a15 \
		-d unimp  -semihosting-config enable,target=native \
		-m 1057 \
		-bios $(ROOT)/out/bios-qemu/bios.bin \
		$(QEMU_EXTRA_ARGS) )


ifneq ($(filter check,$(MAKECMDGOALS)),)
CHECK_DEPS := all
endif

check-args := --bios $(ROOT)/out/bios-qemu/bios.bin
ifneq ($(TIMEOUT),)
check-args += --timeout $(TIMEOUT)
endif

QEMU_SMP ?= 1
check: $(CHECK_DEPS)
	cd $(BINARIES_PATH) && \
		export QEMU=$(ROOT)/qemu/arm-softmmu/qemu-system-arm && \
		export QEMU_SMP=$(QEMU_SMP) && \
		expect $(ROOT)/build/qemu-check.exp -- $(check-args) || \
		(if [ "$(DUMP_LOGS_ON_ERROR)" ]; then \
			echo "== $$PWD/serial0.log:"; \
			cat serial0.log; \
			echo "== end of $$PWD/serial0.log:"; \
			echo "== $$PWD/serial1.log:"; \
			cat serial1.log; \
			echo "== end of $$PWD/serial1.log:"; \
		fi; false)

check-only: check

check-clean:
	rm -f serial0.log serial1.log
