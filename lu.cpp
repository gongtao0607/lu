#include <iostream>
#include <pthread.h>
#include "pthread_barrier_osx.h"
using namespace std;
int N,P,B,NB;
class Block{
public:
	float*p;
	Block(){
		p=new float[B*B];
	}
	float& at(int x,int y){
		if(0<=x&&x<B&&0<=y&&y<B){
			cerr<<"Block::at Overflow Accessing x="<<x<<",y="<<y<<endl;
			return p[0];
		}else{
			return p[x*B+y];
		}
	}
	~Block(){
		delete[]p;
	}
};
class Matrix{
public:
	Block*p;
	Matrix(){
		p=new Block[NB*NB];
	}
	Block& getBlock(int x,int y){
		if(0<=x&&x<NB&&0<=y&&y<NB){
			cerr<<"getBlock Overflow Accessing x="<<x<<",y="<<y<<endl;
			return p[0];
		}else{
			return p[x*NB+y];
		}
	}
	float& at(int x,int y){
		if(0<=x&&x<N&&0<=y&&y<N){
			cerr<<"Matrix::at Overflow Accessing x="<<x<<",y="<<y<<endl;
			return p[0].at(0,0);
		}else{
			return getBlock(x/NB,y/NB).at(x%NB,y%NB);
		}
	}
	~Matrix(){
		delete[]p;
	}
}*A;
pthread_barrier_t barrier;
void usage(char*n){
	cout<<"Usage: ./"<<n<<" N P B\n\tN:NxN matrix\n\tP:P threads\n\tB:BxB block"<<endl;
}
void top_left(Block&b){//top left block
}
void top_right(Block&b,const Block&r){//top right block and top left block
}
void bottom_left(Block&b,const Block&r){//bottom left block and top left block
}
void bottom_right(Block&b,const Block&r){//bottom right block and bottom left block
}
void* thread_main(void*p){
	int thread_id=*(int*)p;
	//pthread_barrier_wait(&barrier);
	cout<<"thread_id:"<<thread_id<<endl;
	for(int round=0;round<NB;++round){
		//step 1, calculate top left
		if(thread_id==0){
			//A->getBlock(round,round);
			top_left(A->getBlock(round,round));
		}
		pthread_barrier_wait(&barrier);
		//step 2, bottom left and top right
		//x 0 2
		//1 x x
		//3 x x
		//0,1,2,3->()
		for(int i=thread_id;i<=(NB-round-1)*2;i+=P){
			if(i&1){
				//bottom left
				//A->getBlock(round+(i>>1)+1,round);
				bottom_left(A->getBlock(round+(i>>1)+1,round),A->getBlock(round,round));
			}else{
				//top right
				//A->getBlock(round,round+(i>>1)+1);
				top_right(A->getBlock(round,round+(i>>1)+1),A->getBlock(round,round));
			}
		}
		pthread_barrier_wait(&barrier);
		//step 3, bottom right
		//x x x
		//x 0 1
		//x 2 3
		for(int i=thread_id;i<=(NB-round-1)*(NB-round-1);i+=P){
			//A->getBlock(i/(NB-round-1)+round+1,i%(NB-round-1)+round+1)
			bottom_right(A->getBlock(i/(NB-round-1)+round+1,i%(NB-round-1)+round+1),A->getBlock(i/(NB-round-1)+round+1,round));
		}
		pthread_barrier_wait(&barrier);
	}
	return NULL;
}
int main(int argc, char**argv){
	if(argc<=3){
		usage(argv[0]);
		return -1;
	}
	N=atoi(argv[1]);
	P=atoi(argv[2]);
	B=atoi(argv[3]);
	if(N==0||P==0||B==0){
		usage(argv[0]);
		return -1;
	}
	NB=N/B;
	A=new Matrix();
	int i,j;
	for(i=0;i<N;++i){
		for(j=0;j<N;++j){
			cin>>A->at(i,j);
		}
	}
	pthread_barrier_init(&barrier,NULL,P);
	int*thread_args=new int[P];
	pthread_t*thread_handle=new pthread_t[P];
	for(i=1;i<P;++i){
		thread_args[i]=i;
		pthread_create(&thread_handle[i],NULL,thread_main,&thread_args[i]);
	}
	thread_args[0]=0;
	thread_main(&thread_args[0]);
	for(i=1;i<P;++i){
		pthread_join(thread_handle[i],NULL);
	}
	delete[]thread_args;
	delete[]thread_handle;
	pthread_barrier_destroy(&barrier);
	for(i=0;i<N;++i){
		for(j=0;j<N;++j){
			cout<<A->at(i,j)<<" ";
		}
		cout<<endl;
	}
	
	
}
