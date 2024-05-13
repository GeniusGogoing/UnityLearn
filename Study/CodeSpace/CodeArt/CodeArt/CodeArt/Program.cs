using System;
using System.Collections;
using System.Collections.Generic;
using System.Numerics;
using System.Text;

namespace CodeArt
{
    class Program
    {
        static void Main(string[] args)
        {
            Solution solution = new Solution();
        }
    }

    public class Solution
    {
        public int Trap(int[] height)
        {
            // 接水量求和
            int res = 0;
            int left = 1;
            int right = height.Length - 2;
            // 记录left左侧最高列高
            int maxLeft = 0; 
            // 记录right右侧最高列高
            int maxRight = 0;
            // 当前列的接水量 等于 左右两边最高列里较矮的列-当前列的高度（前提是比当前列高）
            // 对于某一列左边或者右边的最高列 等于 前一列的左边或右边的最高列和当前列左边或右边的列的高度中的较大值
            // 上述过程是一个递推式 且可以优化dp空间
            // 不仅可以优化空间 还可以进一步优化过程 让问题在一个循环中解决
            // 那就是 当前列只在意两边列中较矮的那个 假设左边的列比右端的列矮 那么不管右边其他列什么情况 此时只需要计算左边最高列即可
            // 反之 假设右边的列比左端的列矮或者相等 那么不管左边其他列什么情况 只需要计算右边的最高列即可
            // 这两种情况的总和 就是所有的接水量
            for (int i = 1; i < height.Length-1; i++)
            {
                if (height[left-1] < height[right + 1])
                {
                    maxLeft = Math.Max(maxLeft, height[left-1]);
                    if(maxLeft > height[left])
                    {
                        res += (maxLeft - height[left]);
                    }
                    left++;
                }
                else
                {
                    maxRight = Math.Max(maxRight, height[right+1]);
                    if(maxRight > height[right])
                        res += (maxRight - height[right]);
                    right--;
                }
            }
            return res;
        }
    }
}
