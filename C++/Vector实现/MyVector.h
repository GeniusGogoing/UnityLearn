#pragma once
typedef int Rank;
#define DEFAULT_CAPACITY = 3
template <typename T> class MyVector
{
private:
	//��ģ
	int _size;
	//����
	int _capacity;
	//������
	T* _elem;

public:
	//���캯��
	MyVector(int c = DEFAULT_CAPACITY);
	int size() { return _size; }
};
