
include CONFIG

MATH = $(patsubst %.cpp,%.o,$(wildcard Math/*.cpp))

TOOLS = $(patsubst %.cpp,%.o,$(wildcard Tools/*.cpp))

NETWORK = $(patsubst %.cpp,%.o,$(wildcard Networking/*.cpp))

PROCESSOR = $(patsubst %.cpp,%.o,$(wildcard Processor/*.cpp)) Protocols/ShamirOptions.o

FHEOBJS = $(patsubst %.cpp,%.o,$(wildcard FHEOffline/*.cpp FHE/*.cpp)) Protocols/CowGearOptions.o

GC = $(patsubst %.cpp,%.o,$(wildcard GC/*.cpp)) $(PROCESSOR)
GC_SEMI = GC/SemiPrep.o GC/square64.o GC/Semi.o

OT = $(patsubst %.cpp,%.o,$(wildcard OT/*.cpp))

COMMONOBJS = $(MATH) $(TOOLS) $(NETWORK) GC/square64.o Processor/OnlineOptions.o Processor/BaseMachine.o Processor/DataPositions.o Processor/ThreadQueues.o Processor/ThreadQueue.o
COMPLETE = $(COMMON) $(PROCESSOR) $(FHEOFFLINE) $(TINYOTOFFLINE) $(GC) $(OT)
YAO = $(patsubst %.cpp,%.o,$(wildcard Yao/*.cpp)) $(OT) BMR/Key.o
MINI_OT = OT/OTTripleSetup.o OT/BaseOT.o $(LIBQOKDOT)
VMOBJS = $(PROCESSOR) $(COMMONOBJS) $(LIBQOKDOT) GC/square64.o GC/Instruction.o OT/OTTripleSetup.o OT/BaseOT.o
VM = $(MINI_OT) $(SHAREDLIB)
COMMON = $(SHAREDLIB)
TINIER =  Machines/Tinier.o $(OT)
SPDZ = Machines/SPDZ.o $(TINIER)	

LIB = libSPDZ.a
SHAREDLIB = libSPDZ.so
FHEOFFLINE = libFHE.so
LIBRELEASE = librelease.a
LIBQOKDOT = OTKeys/OTKeys/lib/libuirotk.a
STATIC_OTE = local/lib/liblibOTe.a
SHARED_OTE = local/lib/liblibOTe.so

ifeq ($(USE_KOS), 0)
ifeq ($(USE_SHARED_OTE), 1)
OT += $(SHARED_OTE) local/lib/libcryptoTools.so
else
OT += $(STATIC_OTE) local/lib/libcryptoTools.a
endif
endif

# used for dependency generation
OBJS = $(patsubst %.cpp,%.o,$(wildcard */*.cpp */*/*.cpp)) $(STATIC_OTE)
DEPS := $(wildcard */*.d */*/*.d)

# never delete
.SECONDARY: $(OBJS)

all: arithmetic binary gen_input online offline externalIO export
vm: arithmetic binary

arithmetic: semi-party.x mascot-party.x
binary: yao

-include $(DEPS)
include $(wildcard *.d static/*.d)

$(OBJS): CONFIG CONFIG.mine
CONFIG.mine:
	touch CONFIG.mine

%.o: %.cpp
	$(CXX) -o $@ $< $(CFLAGS) -MMD -MP -c

ifeq ($(OS), Darwin)
setup: mac-setup
else
setup: maybe-boost linux-machine-setup
endif

tldr: setup
	$(MAKE) mascot-party.x
	mkdir Player-Data 2> /dev/null; true

ifeq ($(ARM), 1)
$(patsubst %.cpp,%.o,$(wildcard */*.cpp */*/*.cpp)): deps/simde/simde deps/sse2neon/sse2neon.h
endif

CFLAGS += -fPIC
LDLIBS += -Wl,-rpath -Wl,$(CURDIR) -lcurl -ljansson -lcrypto -lssl -luuid -lexplain -lb64

$(SHAREDLIB): $(PROCESSOR) $(COMMONOBJS) GC/square64.o GC/Instruction.o
	$(CXX) $(CFLAGS) -shared -o $@ $^ $(LDLIBS)

$(FHEOFFLINE): $(FHEOBJS) $(SHAREDLIB)
	$(CXX) $(CFLAGS) -shared -o $@ $^ $(LDLIBS)

static/%.x: Machines/%.o $(LIBRELEASE) $(LIBQOKDOT) local/lib/libcryptoTools.a
	$(MAKE) static-dir
	$(CXX) -o $@ $(CFLAGS) $^ -Wl,-Map=$<.map -Wl,-Bstatic -static-libgcc -static-libstdc++ $(LIBRELEASE) -lcryptoTools $(LIBQOKDOT) $(BOOST) $(LDLIBS) -Wl,-Bdynamic -ldl

static-dir:
	@ mkdir static 2> /dev/null; true

EXPORT_VM = $(patsubst %.cpp, %.o, $(wildcard Machines/export-*.cpp))
.SECONDARY: $(EXPORT_VM)

export: $(patsubst Utils/%.cpp, %.x, $(wildcard Utils/export*.cpp))

yao-party.x: $(YAO)
static/yao-party.x: $(YAO)

yao-clean:
	-rm Yao/*.o

%.x: Utils/%.o $(COMMON)
	$(CXX) -o $@ $(CFLAGS) $^ $(LDLIBS)

%.x: Machines/%.o $(MINI_OT) $(SHAREDLIB)
	$(CXX) -o $@ $(CFLAGS) $^ $(LDLIBS) $(SHAREDLIB)

semi-party.x: $(OT)  $(GC_SEMI)
mascot-party.x: $(SPDZ)
static/mascot-party.x: $(SPDZ)
OT/BaseOT.o: OTKeys/Makefile

$(LIBQOKDOT): OTKeys/Makefile

OTKeys/Makefile:
	-mv OTKeys_$(KEY_REQUEST_INTERFACE) OTKeys
	$(MAKE) -C OTKeys/OTKeys

.PHONY: Programs/Circuits
Programs/Circuits:
	git submodule update --init Programs/Circuits || git clone https://github.com/mkskeller/bristol-fashion Programs/Circuits

deps/libOTe/libOTe:
	git submodule update --init --recursive deps/libOTe || git clone --recurse-submodules https://github.com/mkskeller/softspoken-implementation deps/libOTe
boost: deps/libOTe/libOTe
	cd deps/libOTe; \
	python3 build.py --setup --boost --install=$(CURDIR)/local
maybe-boost: deps/libOTe/libOTe
	cd `mktemp -d`; \
	PATH="$(CURDIR)/local/bin:$(PATH)" cmake $(CURDIR)/deps/libOTe || \
	{ cd -; make boost; }

OTE_OPTS += -DENABLE_SOFTSPOKEN_OT=ON -DCMAKE_CXX_COMPILER=$(CXX) -DCMAKE_INSTALL_LIBDIR=lib

ifeq ($(ARM), 1)
OTE_OPTS += -DENABLE_AVX=OFF -DENABLE_SSE=OFF
else
ifeq ($(AVX_OT), 0)
OTE_OPTS += -DENABLE_AVX=OFF
else
OTE_OPTS += -DENABLE_AVX=ON -DENABLE_SSE=ON
endif
endif

ifeq ($(USE_SHARED_OTE), 1)
OTE = $(SHARED_OTE)
else
OTE = $(STATIC_OTE)
endif

local/lib/libcryptoTools.a: $(STATIC_OTE)
local/lib/libcryptoTools.so: $(SHARED_OTE)

ifeq ($(USE_KOS), 0)
OT/OTExtensionWithMatrix.o: $(OTE)
endif

local/lib/liblibOTe.a: deps/libOTe/libOTe
	make maybe-boost; \
	cd deps/libOTe; \
	PATH="$(CURDIR)/local/bin:$(PATH)" python3 build.py --install=$(CURDIR)/local -- -DBUILD_SHARED_LIBS=0 $(OTE_OPTS) && \
	touch ../../local/lib/liblibOTe.a

$(SHARED_OTE): deps/libOTe/libOTe maybe-boost
	cd deps/libOTe; \
	python3 build.py --install=$(CURDIR)/local -- -DBUILD_SHARED_LIBS=1 $(OTE_OPTS)

cmake:
	wget https://github.com/Kitware/CMake/releases/download/v3.24.1/cmake-3.24.1.tar.gz
	tar xzvf cmake-3.24.1.tar.gz
	cd cmake-3.24.1; \
	./bootstrap --parallel=8 --prefix=../local && make -j8 && make install
	
mac-setup: mac-machine-setup
	brew install openssl boost libsodium gmp yasm ntl cmake

linux-machine-setup:
mac-machine-setup:

deps/simde/simde:
	git submodule update --init deps/simde || git clone https://github.com/simd-everywhere/simde deps/simde

deps/sse2neon/sse2neon.h:
	git submodule update --init deps/sse2neon || git clone https://github.com/DLTcollab/sse2neon deps/sse2neon

clean-deps:
	-rm -rf local/lib/liblibOTe.* deps/libOTe/out pq/*.so

clean: #clean-deps
	-rm -f */*.o *.o */*.d *.d *.x core.* *.a gmon.out */*/*.o static/*.x *.so
