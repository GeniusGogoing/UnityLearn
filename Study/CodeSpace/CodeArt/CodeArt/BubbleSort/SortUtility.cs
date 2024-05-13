using System;
using System.Collections;
using System.Collections.Generic;
using Heap;

namespace SortTool
{
    abstract class SortUtility<T> where T : IComparable<T>
    {
        protected class InternalComparison : IComparer<T>
        {
            public int Compare(T? x, T? y)
            {
                return x.CompareTo(y);
            }
        }

        protected class CustomComparison : IComparer<T> 
        {
            public Comparison<T> _comparison;
            public CustomComparison(Comparison<T> comparison)
            {
                _comparison = comparison;
            }
            public int Compare(T? x, T? y)
            {
                return _comparison(x, y);
            }
        }

        public abstract void Sort(IList<T> datas, Comparison<T> specialComparer = null);
    }

    // 冒泡排序
    class BubbleSortUtility<T> : SortUtility<T>  where T : IComparable<T>
    {
        public override void Sort(IList<T> datas, Comparison<T> specialComparer = null)
        {
            int length = datas.Count;
            T swapper;
            IComparer<T> comparer;
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            for (int i = 0; i < length; i++)
            {
                for (int j = 0; j < length - 1 - i; j++)
                {
                    if (comparer.Compare(datas[j], datas[j + 1]) > 0)
                    {
                        swapper = datas[j + 1];
                        datas[j + 1] = datas[j];
                        datas[j] = swapper;
                    }
                }
            }
        }
    }

    // 选择排序
    class SelectSortUtility<T> : SortUtility<T> where T : IComparable<T>
    {
        public override void Sort(IList<T> datas, Comparison<T> specialComparer = null)
        {
            IComparer<T> comparer;
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            int length = datas.Count;
            T swapper;
            int maxIndex = 0;

            for (int i = 0; i < length; i++)
            {
                maxIndex = i;
                for (int j = i; j < length; j++)
                {
                    if (comparer.Compare(datas[j], datas[maxIndex]) > 0)
                    {
                        maxIndex = j;
                    }
                }
                swapper = datas[i];
                datas[i] = datas[maxIndex];
                datas[maxIndex] = swapper;
            }
        }
    }

    //插入排序
    class InsertSortUtility<T> : SortUtility<T> where T : IComparable<T>
    {
        public override void Sort(IList<T> datas, Comparison<T> specialComparer = null)
        {
            IComparer<T> comparer;
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            int length = datas.Count;
            T swapper;

            for (int i = 1; i < length; i++)
            {
                for (int j = i; j > 0; j--)
                {
                    if (comparer.Compare(datas[j], datas[j - 1]) < 0)
                    {
                        swapper = datas[j];
                        datas[j] = datas[j - 1];
                        datas[j - 1] = swapper;
                    }
                    else
                    {
                        break;
                    }
                }
            }
        }
    }

    /// <summary>
    /// 希尔排序
    /// 宏观分组 分别插入排序 直到有序
    /// 历史上首个平均复杂度进入n^2的排序算法 不过最坏情况还是n^2
    /// 靠 但是实际上可以跟归并排序的耗时差不多！
    /// </summary>
    /// <typeparam name="T"></typeparam>
    /// <typeparam name="T"></typeparam>
    class ShellSortUtility<T> : SortUtility<T> where T : IComparable<T>
    {
        public override void Sort(IList<T> datas, Comparison<T> specialComparer = null)
        {
            IComparer<T> comparer;
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            int length = datas.Count;
            T temp;

            for (int gap = length / 2; gap > 0; gap /= 2)
            {
                //分组插入排序
                //Console.WriteLine("gap: "+gap);
                for (int i = gap; i < length; i++)
                {
                    // 记录当前待插入值
                    int j = i;
                    temp = datas[j];
                    for (; j > 0; j -= gap)
                    {
                        if (j - gap >= 0 && comparer.Compare(temp, datas[j - gap]) < 0)
                        {
                            datas[j] = datas[j - gap];
                        }
                        else
                        {
                            break;
                        }
                    }
                    datas[j] = temp;
                }
            }
        }
    }

    /// <summary>
    /// 归并排序 nlogn 稳定
    /// 分而治之 重点在于合
    /// </summary>
    /// <typeparam name="T"></typeparam>
    /// <typeparam name="T"></typeparam>
    class MergeSortUtility<T> : SortUtility<T> where T : IComparable<T>
    {
        IComparer<T> comparer;
        public override void Sort(IList<T> datas, Comparison<T> specialComparer = null)
        {
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            int length = datas.Count;

            // 划分 然后 合并
            SortCore(datas, 0, length);
        }

        public void SortCore(IList<T> datas, int lo, int hi)
        {
            if (hi - lo <= 1)
            {
                return;
            }
            int mi = (lo + hi) / 2;
            SortCore(datas, lo, mi);
            SortCore(datas, mi, hi);
            Merge(datas, lo, mi, hi);
        }

        public void Merge(IList<T> datas, int lo, int mi, int hi)
        {
            int i = 0;
            int j = mi;
            int m = lo;
            IList<T> bDatas = new List<T>();
            for (int k = lo; k < mi; k++)
            {
                bDatas.Add(datas[k]);
            }
            for (; i < mi - lo;)
            {
                if (j >= hi || comparer.Compare(bDatas[i], datas[j]) <= 0)
                {
                    datas[m++] = bDatas[i++];
                }
                else
                {
                    datas[m++] = datas[j++];
                }
            }
        }
    }

    /// <summary>
    /// 快速排序 不稳定
    /// 分而治之 重点在于分 确定轴点
    /// </summary>
    /// <typeparam name="T"></typeparam>
    /// <typeparam name="T"></typeparam>
    class QuickSortUtility<T> : SortUtility<T> where T : IComparable<T>
    {
        IComparer<T> comparer;
        public override void Sort(IList<T> datas, Comparison<T> specialComparer = null)
        {
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            int length = datas.Count;

            SortCore(datas, 0, length - 1);
        }

        private void SortCore(IList<T> datas, int lo, int hi)
        {
            //Console.WriteLine($"lo: {lo} hi: {hi}");
            if (hi - lo < 1)
            {
                return;
            }
            int pivot = MakePivot(datas, lo, hi);
            // 轴点在整个序列中的位置是确定有序的 为了保证问题规模的单调递减 不能将轴点继续划入序列范围
            SortCore(datas, lo, pivot - 1);
            SortCore(datas, pivot + 1, hi);
        }

        private int MakePivot(IList<T> datas, int lo, int hi)
        {
            int pivot = lo;
            T pivotData = datas[lo];
            bool isLeft = true;
            T swapper;
            while (lo < hi)
            {
                if (isLeft)
                {
                    while (hi > lo && comparer.Compare(datas[hi], pivotData) > 0)
                    {
                        hi--;
                    }
                    swapper = datas[hi];
                    datas[hi] = pivotData;
                    datas[lo] = swapper;
                    pivot = lo;
                    isLeft = false;
                }
                else
                {
                    while (lo < hi && comparer.Compare(datas[lo], pivotData) <= 0)
                    {
                        lo++;
                    }
                    swapper = datas[lo];
                    datas[lo] = pivotData;
                    datas[hi] = swapper;
                    pivot = hi;
                    isLeft = true;
                }
            }
            return pivot;
        }
    }

    /// <summary>
    /// 堆排序 O(nlogn) 不稳定
    /// </summary>
    /// <typeparam name="T"></typeparam>
    /// <typeparam name="T"></typeparam>
    class HeapSortUtility<T> : SortUtility<T> where T : IComparable<T>
    {
        IComparer<T> comparer;
        Heap<T> heap;
        public override void Sort(IList<T> datas, Comparison<T> specialComparer = null)
        {
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            heap = new Heap<T>(datas,comparer);
            int i = heap.Count;
            while(i-- > 0)
            {
                heap.DelTop();
            }
        }
    }

    // 以下是适用于非负整数 数据量很大且取值范围相比较小情况的排序算法

    /// <summary>
    /// 桶排序 O(n)+O(k)O(n/k*log(n/k)) k = 分区大小
    /// 计数排序就是让桶的间隔变成1 O(n+m)的效率 但是O(m)的内存 m = 取值范围
    /// 基数排序 也是桶排序的变体 每一位就是一个桶 最大的位数就是桶的个数 O(kn) k = 位数 每个桶采用计数排序
    /// </summary>
    /// <typeparam name="T"></typeparam>
    class BucketSortUtility : SortUtility<int> 
    {
        IComparer<int> comparer;
        int bucketInterval = 5;
        List<List<int>> buckets;
        public override void Sort(IList<int> datas, Comparison<int> specialComparer = null)
        {
            if (specialComparer == null)
            {
                comparer = new InternalComparison();
            }
            else
            {
                comparer = new CustomComparison(specialComparer);
            }

            if(datas.Count == 0)
            {
                return;
            }
            // 首先确定上下限
            int min = datas[0];
            int max = datas[0];
            for(int i = 1; i < datas.Count; i++)
            {
                if (comparer.Compare(datas[i],min) < 0)
                {
                    min = datas[i];
                }

                if (comparer.Compare(datas[i], max) > 0)
                {
                    max = datas[i];
                }
            }
            // 由于不同排序顺序 修正min 和 max
            bool needReverse = false;
            if(min > max)
            {
                int temp = min;
                min = max;
                max = temp;
                needReverse = true;
            }
            // 划分桶区间
            //Console.WriteLine("min: "+min+" max: "+ max);
            buckets = new List<List<int>>();
            for(int i = min;i < max; i+=bucketInterval)
            {
                buckets.Add(new List<int>());
            }
            //Console.WriteLine("bucket num: "+buckets.Count);
            // 分配到桶
            foreach (int item in datas)
            {
                if(needReverse)
                {
                    buckets[(max - item) / bucketInterval].Add(item);
                }
                else
                {
                    buckets[(item - min) / bucketInterval].Add(item);
                }
            }
            // 桶分别排序
            SortUtilityFactory<int> factory = new SortUtilityFactory<int>();
            var sortUtility = factory.CreateSortUtility((int)SortEnums.Merge);
            foreach (var bucket in buckets)
            {
                sortUtility.Sort(bucket, specialComparer);
            }
            // 把所有的桶按序结合得到排序结果
            int index = 0;
            for(int i = 0; i < buckets.Count; i++)
            {
                for(int j = 0; j < buckets[i].Count; j++)
                {
                    datas[index++] = buckets[i][j];
                }
            }
        }
    }

}
