using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Heap
{
    public class Heap<T> where T : IComparable<T>
    {
        IList<T> _data;
        int _count = 0;
        public int Count
        {
            get { return _count; }
            set { _count = value; }
        }
        IComparer<T> _comparer;
        struct DefaultComparer : IComparer<T>
        {
            public int Compare(T x, T y)
            {
                return x.CompareTo(y);
            }
        }
        DefaultComparer defaulComparer;
        // 批量建堆
        public Heap(IList<T> values, IComparer<T>? comparer = null)
        {
            if (comparer == null)
            {
                _comparer = defaulComparer;
            }
            else
            {
                _comparer = comparer;
            }

            Heapify(values);
        }

        // 批量建堆 自下而上的下滤 O(n)
        public void Heapify(IList<T> values)
        {
            _data = values;
            Count = _data.Count;
            int startIndex = Count / 2 - 1;
            while (startIndex >= 0)
            {
                InfiltrateDown(startIndex--);
            }
        }

        // 获取父节点序号
        protected int GetParentIndex(int index)
        {
            return (index - 1) >> 1;
        }

        // 获取左孩子节点序号
        protected int GetLeftChildIndex(int index)
        {
            return (index << 1) + 1;
        }

        // 获取右孩子节点序号
        protected int GetRightChildIndex(int index)
        {
            return (index + 1) << 1;
        }

        // 是否为合法序号
        protected bool IsValidIndex(int index)
        {
            return index < Count;
        }

        // 给定序号中 找到可以作为父节点的序号
        protected int GetProperParentIndex(int a, int b, int c)
        {
            T flag;
            int res = -1;
            List<int> list = new List<int>();
            if (a < Count)
            {
                list.Add(a);
            }
            if (b < Count)
            {
                list.Add(b);
            }
            if ((c < Count))
            {
                list.Add(c);
            }
            if (list.Count == 0)
            {
                throw new Exception("no proper index");
            }
            flag = _data[list[0]];
            res = list[0];
            for (int i = 1; i < list.Count; i++)
            {
                if (_comparer.Compare(_data[list[i]], flag) > 0)
                {
                    flag = _data[list[i]];
                    res = list[i];
                }
            }
            return res;
        }

        // 插入 上滤 O(logn)
        public int Insert(T value)
        {
            _data.Add(value);
            int insertIndex = Count - 1;
            int parentIndex = GetParentIndex(insertIndex);
            T temp;
            while (parentIndex >= 0 && _comparer.Compare(_data[parentIndex], _data[insertIndex]) < 0)
            {
                temp = _data[parentIndex];
                _data[parentIndex] = _data[insertIndex];
                _data[insertIndex] = temp;
                insertIndex = parentIndex;
                parentIndex = GetParentIndex(insertIndex);
            }
            return insertIndex;
        }

        // 删除 下滤 O(logn)
        public T DelTop()
        {
            T res = _data[0];
            _data[0] = _data[Count - 1];
            _data[Count - 1] = res;
            Count--;
            InfiltrateDown(0);
            return res;
        }

        public void InfiltrateDown(int index)
        {
            int curIndex = index;
            int lChildIndex = GetLeftChildIndex(curIndex);
            int rChildIndex = GetRightChildIndex(curIndex);
            T temp;
            while (curIndex < Count)
            {
                int properParentIndex = GetProperParentIndex(curIndex, lChildIndex, rChildIndex);
                if (curIndex == properParentIndex)
                {
                    // 有序 可退出
                    break;
                }

                temp = _data[curIndex];
                _data[curIndex] = _data[properParentIndex];
                _data[properParentIndex] = temp;

                curIndex = properParentIndex;
                lChildIndex = GetLeftChildIndex(curIndex);
                rChildIndex = GetRightChildIndex(curIndex);
            }
        }

        public T GetTop()
        {
            return _data[0];
        }

        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < Count; i++)
            {
                sb.Append(_data[i] + " ");
            }
            return sb.ToString();
        }
    }
}
