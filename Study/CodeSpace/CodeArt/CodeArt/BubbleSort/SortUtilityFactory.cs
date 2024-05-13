using System;
using System.Collections;
using System.Text;

namespace SortTool
{
    public enum SortEnums
    {
        Bubble = 1,
        Select = 2,
        Insert = 3,
        Shell = 4,
        Merge = 5,
        Quick = 6,
        Heap = 7,
        Bucket = 8,
    }
    class SortUtilityFactory<T> where T : IComparable<T>
    {
       
        public SortUtility<T> CreateSortUtility(int sortEnum)
        {
            SortEnums sortEnums = (SortEnums)sortEnum;
            switch (sortEnum)
            {
                case (int)SortEnums.Bubble:
                    return new BubbleSortUtility<T>();
                case (int)SortEnums.Select:
                    return new SelectSortUtility<T>();
                case (int)SortEnums.Insert:
                    return new InsertSortUtility<T>();
                case (int)SortEnums.Shell:
                    return new ShellSortUtility<T>();
                case (int)SortEnums.Merge:
                    return new MergeSortUtility<T>();
                case (int)SortEnums.Quick:
                    return new QuickSortUtility<T>();
                case (int)SortEnums.Heap:
                    return new HeapSortUtility<T>();
                default:
                    throw new NotImplementedException();
            }
        }
    }

    class SortUtilityFactory
    {
        public SortUtility<int> CreateSortUtility(int sortEnum)
        {
            SortEnums sortEnums = (SortEnums)sortEnum;
            switch (sortEnum)
            {
                case (int)SortEnums.Bucket:
                    return new BucketSortUtility();
                default:
                    throw new NotImplementedException();
            }
        }
    }
}
