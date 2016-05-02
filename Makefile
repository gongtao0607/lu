LDLIBS += -lpthread
#CPPFLAGS += -g
all:lucpu lucpu-non lucuda lucuda-non
lucpu:lucpu.cpp
	g++ $(CPPFLAGS) -DCONTIGUOUS $^ -o $@ $(LDLIBS)
lucpu-non:lucpu.cpp
	g++ $(CPPFLAGS) $^ -o $@ $(LDLIBS)
lucuda:lu.cu
	/Developer/NVIDIA/CUDA-7.5/bin/nvcc $(CPPFLAGS) -DCONTIGUOUS $^ -o $@
lucuda-non:lu.cu
	/Developer/NVIDIA/CUDA-7.5/bin/nvcc $(CPPFLAGS) $^ -o $@
lucpu.cpp:lu.cu
	cp lu.cu lucpu.cpp
clean:
	rm -f lucpu lucuda lucuda-non lucpu-non lucpu.cpp
	rm -rf lucpu.dSYM lucuda.dSYM
