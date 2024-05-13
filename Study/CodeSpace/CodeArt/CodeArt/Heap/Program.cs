namespace Heap
{
    internal class Program
    {
        static void Main(string[] args)
        {
            Heap<int> heap = new Heap<int> (new List<int> { 3,1,5,2,4,10,7,5,6,8});
            heap.Insert (2);
            Console.WriteLine(heap);
            heap.DelTop();
            Console.WriteLine(heap);
        }
    }
}