基本通配符
通配符	说明	示例	匹配
*	匹配任意数量的字符（不跨目录）	*.txt	file.txt, report.txt
     ?	匹配单个字符	file?.txt	file1.txt, filea.txt
     [...]	匹配方括号中的任意一个字符	[a-z]	a.txt, b.log
     [0-9]	匹配0-9的任意数字	file[0-9].txt	file1.txt, file5.txt
     **	匹配任意数量的目录（跨目录）	**/*.log	app.log, logs/app.log, logs/subdir/app.log
     {...}	分组匹配	*. {log,txt}	.log, .txt 文件
     [!...] 或 [^...]	匹配不在指定范围内的字符	[!0-9]	非数字字符
     🧠 详细规则
1. * (星号)
     匹配任意数量的字符（包括0个）
     不跨目录边界（即不会匹配子目录中的文件）
     例如：*.txt 匹配当前目录下的所有.txt文件，但不匹配子目录中的
2. ** (双星号)
   跨目录匹配，匹配任意数量的目录和子目录
   必须单独使用（左右必须是路径分隔符）
   例如：**/*.log 匹配当前目录及所有子目录中的.log文件
   例如：a/**/z 匹配 a/z, a/b/z, a/b/c/z 等
3. ? (问号)
   匹配单个字符
   例如：file?.txt 匹配 file1.txt, filea.txt，但不匹配 file12.txt
4. [...] (方括号)
   匹配方括号中指定的字符集
   [abc] 匹配a、b或c
   [a-z] 匹配a-z之间的任意小写字母
   [0-9] 匹配0-9之间的任意数字
   [!0-9] 或 [^0-9] 匹配非数字字符
5. {...} (花括号)
   分组匹配多个模式
   例如：*. {log,txt} 匹配以.log或.txt结尾的文件
   例如：{*.log,*.txt} 匹配.log和.txt文件
   例如：src/{a,b}.js 匹配a.js和b.js


https://www.elastic.co/docs/reference/beats/filebeat/filebeat-input-log
