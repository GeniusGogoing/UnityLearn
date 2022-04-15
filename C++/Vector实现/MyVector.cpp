#include "MyVector.h"

template <typename T>
MyVector<T>::MyVector(int c) : _capacity(c), _size(0), _elem(new T[c]) {}