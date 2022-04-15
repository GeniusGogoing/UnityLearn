#pragma once
typedef int Rank;
#define DEFAULT_CAPACITY = 3
template <typename T> class MyVector
{
private:
	//规模
	int _size;
	//容量
	int _capacity;
	//数据区
	T* _elem;

public:
	//构造函数
	MyVector(int c = DEFAULT_CAPACITY);
	int size() { return _size; }
};
