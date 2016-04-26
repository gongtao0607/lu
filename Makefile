LDLIBS += -lpthread
#CPPFLAGS += -g
all:lucpu lucuda
lucpu:lu.cu
	cp lu.cu lucpu.cpp
	g++ $(CPPFLAGS) $^ -o $@ $(LDLIBS)
lucuda:lu.cu
	/Developer/NVIDIA/CUDA-7.5/bin/nvcc $(CPPFLAGS) $^ -o $@
clean:
	rm -f lucpu lucuda lucpu.cpp
	rm -rf lucpu.dSYM lucuda.dSYM
