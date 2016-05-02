LDLIBS += -lpthread
#CPPFLAGS += -g
all:lucpu lucuda
lucpu:lucpu.cpp
	g++ $(CPPFLAGS) $^ -o $@ $(LDLIBS)
lucuda:lu.cu
	/Developer/NVIDIA/CUDA-7.5/bin/nvcc $(CPPFLAGS) $^ -o $@
lucpu.cpp:lu.cu
	cp lu.cu lucpu.cpp
clean:
	rm -f lucpu lucuda lucpu.cpp
	rm -rf lucpu.dSYM lucuda.dSYM
