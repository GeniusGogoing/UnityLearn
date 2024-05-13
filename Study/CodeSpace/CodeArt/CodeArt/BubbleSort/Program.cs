using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection.Metadata.Ecma335;
using Heap;

namespace SortTool
{
    class Program
    {
        static List<int> arrayList = new List<int>();
        static bool showArray = true;
        static int length = 10;
        static void Main(string[] args)
        {
            MakeArray();
            SortUtilityFactory<int> factory = new SortUtilityFactory<int>();
            //SortTest(factory.CreateSortUtility((int)SortEnums.Bubble));
            //SortTest(factory.CreateSortUtility((int)SortEnums.Select));
            //SortTest(factory.CreateSortUtility((int)SortEnums.Insert));
            //SortTest(factory.CreateSortUtility((int)SortEnums.Shell));
            //SortTest(factory.CreateSortUtility((int)SortEnums.Merge));
            //SortTest(factory.CreateSortUtility((int)SortEnums.Quick));
            //SortTest(factory.CreateSortUtility((int)SortEnums.Heap));

            SortUtilityFactory factory2 = new SortUtilityFactory();
            SortTest(factory2.CreateSortUtility((int)SortEnums.Bucket));
        }

        static void MakeArray()
        {
            arrayList.Clear();
            var seed = new Random();
            for (int i = 0; i < length; i++)
            {
                arrayList.Add(seed.Next(101));
                if (showArray)
                {
                    Console.Write(arrayList[i] + " ");
                }
            }
            if (showArray)
            {
                Console.WriteLine();
            }
        }

        static void SortTest<T>(SortUtility<T> sortUtility) where T : IComparable<T>
        {
            Console.WriteLine();
            Console.WriteLine(sortUtility.GetType().Name);

            DateTime before;
            TimeSpan timeSpan;

            List<int> _listSort1 = new List<int>();
            foreach (var item in arrayList)
            {
                _listSort1.Add(item);
            }
            before = DateTime.Now;
            sortUtility.Sort((IList<T>)_listSort1);
            timeSpan = DateTime.Now.Subtract(before);
            if (showArray)
            {
                foreach (var item in _listSort1)
                {
                    Console.Write(item + " ");
                }
                Console.WriteLine();
            }

            Console.WriteLine("usedTime: " + timeSpan.TotalMilliseconds);

            List<int> _listSort2 = new List<int>();
            foreach (var item in arrayList)
            {
                _listSort2.Add(item);
            }
            before = DateTime.Now;
            sortUtility.Sort((IList<T>)_listSort2, new Comparison<T>((a, b) => b.CompareTo(a)));
            timeSpan = DateTime.Now.Subtract(before);
            if (showArray)
            {
                foreach (var item in _listSort2)
                {
                    Console.Write(item + " ");
                }
                Console.WriteLine();
            }
            Console.WriteLine("usedTime: "+ timeSpan.TotalMilliseconds);
        }
    }

   
}
