/******************************************************************************************
 * Data Structures in C++
 * ISBN: 7-302-33064-6 & 7-302-33065-3 & 7-302-29652-2 & 7-302-26883-3
 * Junhui DENG, deng@tsinghua.edu.cn
 * Computer Science & Technology, Tsinghua University
 * Copyright (c) 2003-2019. All rights reserved.
 ******************************************************************************************/

#pragma once

/******************************************************************************************
 * �عؼ���k��Ӧ�Ĳ��������ҵ��׸����ÿ�Ͱ�������������ʱ���ã�
 * ��̽���Զ��ֶ����������ѡȡ���������������̽����Ϊ��
 ******************************************************************************************/
template <typename K, typename V> int Hashtable<K, V>::probe4Free ( const K& k ) {
   int r = hashCode ( k ) % M; //����ʼͰ�������෨ȷ��������
   //*DSA*/printf(" ->%d", r); //�׸���̽��Ͱ��Ԫ��ַ
   while ( ht[r] ) r = ( r + 1 ) % M; //�ز�������Ͱ��̽��ֱ���׸���Ͱ�������Ƿ��������ɾ����ǣ�
//*DSA*/   while (ht[r]) { r = (r+1) % M; printf(" ->%d", r); } printf("\n");
   return r; //Ϊ��֤��Ͱ�����ҵ���װ�����Ӽ�ɢ�б�����Ҫ��������
}