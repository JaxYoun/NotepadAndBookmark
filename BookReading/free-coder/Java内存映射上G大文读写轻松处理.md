# Java内存映射，上G大文件轻松处理

**内存映射文件**(Memory-mapped File)，指的是将一段虚拟内存逐字节映射于一个文件，使得应用程序处理文件如同访问主内存（但在真正使用到这些数据**前**却不会消耗物理内存，也不会有读写磁盘的操作），这要比直接文件读写快几个数量级。

稍微解释一下虚拟内存（很明显，不是物理内存），它是计算机系统内存管理的一种技术。像施了妖法一样使得应用程序认为它拥有连续的可用的内存，实际上呢，它通常是被分隔成多个物理内存的碎片，还有部分暂时存储在外部磁盘存储器上，在需要时进行数据交换。

内存映射文件主要的用处是增加 I/O 性能，特别是针对大文件。对于小文件，内存映射文件反而会导致**碎片空间的浪费**，因为内存映射总是要对齐页边界，最小单位是 4 KiB，一个 5 KiB 的文件将会映射占用 8 KiB 内存，也就会浪费 3 KiB 内存。

java.nio 包使得内存映射变得非常简单，其中的核心类叫做 MappedByteBuffer，字面意思为映射的字节缓冲区。

### 01、使用 MappedByteBuffer 读取文件
假设现在有一个文件，名叫 cmower.txt，里面的内容是：
> 沉默王二，一个有趣的程序员

这个文件放在 `/resource` 目录下，我们可以通过下面的方法获取到它：

```java
ClassLoader classLoader = Cmower.class.getClassLoader();
Path path = Paths.get(classLoader.getResource("cmower.txt").getPath());
```

Path 既可以表示一个目录，也可以表示一个文件，就像 File 那样——当然了，Path 是用来取代 File 的。

然后，从文件中获取一个 channel（通道，对磁盘文件的一种抽象）。

```java
FileChannel fileChannel = FileChannel.open(path);
```

紧接着，调用 FileChannel 类的 map 方法从 channel 中获取 MappedByteBuffer，此类扩展了 `ByteBuffer`——提供了一些内存映射文件的基本操作方法。

```java
MappedByteBuffer mappedByteBuffer = fileChannel.map(mode, position, size);
```

稍微解释一下 map 方法的三个参数。

1）mode 为文件映射模式，分为三种：

- MapMode.READ_ONLY（只读），任何试图修改缓冲区的操作将导致抛出 ReadOnlyBufferException 异常。
- MapMode.READ_WRITE（读/写），任何对缓冲区的更改都会在某个时刻写入文件中。需要注意的是，其他映射同一个文件的程序可能不能立即看到这些修改，多个程序同时进行文件映射的行为依赖于操作系统。
- MapMode.PRIVATE（私有）， 对缓冲区的更改不会被写入到该文件，任何修改对这个缓冲区来说都是私有的。

2）position 为文件映射时的起始位置。

3）`size` 为要映射的区域的大小，必须是非负数，不得大于`Integer.MAX_VALUE`。

一旦把文件映射到内存缓冲区，我们就可以把里面的数据读入到 CharBuffer 中并打印出来。具体的代码示例如下。

```java
CharBuffer charBuffer = null;
ClassLoader classLoader = Cmower.class.getClassLoader();
Path path = Paths.get(classLoader.getResource("cmower.txt").getPath());
try (FileChannel fileChannel = FileChannel.open(path)) {
    MappedByteBuffer mappedByteBuffer = fileChannel.map(MapMode.READ_ONLY, 0, fileChannel.size());
    if (mappedByteBuffer != null) {
        charBuffer = Charset.forName("UTF-8").decode(mappedByteBuffer);
    }
    System.out.println(charBuffer.toString());
} catch (IOException e) {
    e.printStackTrace();
}
```

由于 `decode()` 方法的参数是 MappedByteBuffer，这就意味着我们是从内存中而不是磁盘中读入的文件内容，所以速度会非常快。

### 02、使用 MappedByteBuffer 写入文件

假设现在要把下面的内容写入到一个文件，名叫 cmower1.txt。

> 沉默王二，《Web全栈开发进阶之路》作者

这个文件还没有创建，计划放在项目的 classpath 目录下。

```java
 Path path = Paths.get("cmower1.txt");
```

具体位置见下图所示。

![img](https://imgconvert.csdnimg.cn/aHR0cHM6Ly91cGxvYWQtaW1hZ2VzLmppYW5zaHUuaW8vdXBsb2FkX2ltYWdlcy8xMTc5Mzg5LTc2N2U0NmJhYTAzZWQxYTYucG5n)

然后，创建文件的通道。

```java
FileChannel fileChannel = FileChannel.open(path, StandardOpenOption.READ, StandardOpenOption.WRITE,StandardOpenOption.TRUNCATE_EXISTING)
```

仍然使用的 open 方法，不过增加了 3 个参数，前 2 个很好理解，表示文件可读（READ）、可写（WRITE）；第 3 个参数 TRUNCATE_EXISTING 的意思是如果文件已经存在，并且文件已经打开将要进行 WRITE 操作，则其长度被截断为 0。

紧接着，仍然调用 FileChannel 类的 map 方法从 channel 中获取 MappedByteBuffer。

```java
 MappedByteBuffer mappedByteBuffer = fileChannel.map(MapMode.READ_WRITE, 0, 1024);
```

这一次，我们把模式调整为 MapMode.READ_WRITE，并且指定文件大小为 1024，即 1KB 的大小。然后使用 MappedByteBuffer 中的 put() 方法将 CharBuffer 的内容保存到文件中。具体的代码示例如下。

```java
CharBuffer charBuffer = CharBuffer.wrap("沉默王二，《Web全栈开发进阶之路》作者");
Path path = Paths.get("cmower1.txt");
try (FileChannel fileChannel = FileChannel.open(path, StandardOpenOption.READ, StandardOpenOption.WRITE,
        StandardOpenOption.TRUNCATE_EXISTING)) {
    MappedByteBuffer mappedByteBuffer = fileChannel.map(MapMode.READ_WRITE, 0, 1024);
    if (mappedByteBuffer != null) {
        mappedByteBuffer.put(Charset.forName("UTF-8").encode(charBuffer));
    }
} catch (IOException e) {
    e.printStackTrace();
}
```

可以打开 cmower1.txt 查看一下内容，确认预期的内容有没有写入成功。

### 03、MappedByteBuffer 的遗憾

据说，在 Java 中使用 MappedByteBuffer 是一件非常麻烦并且痛苦的事，主要表现有：

1）一次 map 的大小最好限制在 1.5G 左右，重复 map 会增加虚拟内存回收和重新分配的压力。也就是说，如果文件大小不确定的话，就不太友好。

2）虚拟内存由操作系统来决定什么时候刷新到磁盘，这个时间不太容易被程序控制。

3）MappedByteBuffer 的回收方式比较诡异。

再次强调，这三种说法都是据说，我暂时能力有限，也不能确定这种说法的准确性，很遗憾。

### 04、比较文件操作的处理时间

嗨，朋友，阅读完以上的内容之后，我想你一定对内存映射文件有了大致的了解。但我相信，如果你是一名负责任的程序员，你一定还想知道：内存映射文件的读取速度究竟有多快。

为了得出结论，我叫了另外三名竞赛的选手：InputStream（普通输入流）、BufferedInputStream（带缓冲的输入流）、RandomAccessFile（随机访问文件）。

读取的对象是加勒比海盗4惊涛怪浪.mkv，大小为 1.71G。

1）普通输入流

```
public static void inputStream(Path filename) {
    try (InputStream is = Files.newInputStream(filename)) {
        int c;
        while((c = is.read()) != -1) {
        }
    } catch (IOException e) {
        e.printStackTrace();
    }
}
```

2）带缓冲的输入流

```java
public static void bufferedInputStream(Path filename) {
    try (InputStream is = new BufferedInputStream(Files.newInputStream(filename))) {
        int c;
        while((c = is.read()) != -1) {
        }
    } catch (IOException e) {
        e.printStackTrace();
    }
}
```

3）随机访问文件

```java
public static void randomAccessFile(Path filename) {
    try (RandomAccessFile randomAccessFile  = new RandomAccessFile(filename.toFile(), "r")) {
        for (long i = 0; i < randomAccessFile.length(); i++) {
            randomAccessFile.seek(i);
        }
    } catch (IOException e) {
        e.printStackTrace();
    }
}
```

4）内存映射文件

```java
public static void mappedFile(Path filename) {
    try (FileChannel fileChannel = FileChannel.open(filename)) {
        long size = fileChannel.size();
        MappedByteBuffer mappedByteBuffer = fileChannel.map(MapMode.READ_ONLY, 0, size);
        for (int i = 0; i < size; i++) {
            mappedByteBuffer.get(i);
        }
    } catch (IOException e) {
        e.printStackTrace();
    }
}
```

测试程序也很简单，大致如下：

```java
long start = System.currentTimeMillis();
bufferedInputStream(Paths.get("jialebi.mkv"));
long end = System.currentTimeMillis();
System.out.println(end-start);
```

四名选手的结果如下表所示。

| 方法           | 时间                   |
| -------------- | ---------------------- |
| 普通输入流     | 龟速，没有耐心等出结果 |
| 随机访问文件   | 龟速，没有耐心等下去   |
| 带缓冲的输入流 | 29966                  |
| 内存映射文件   | 914                    |

普通输入流和随机访问文件都慢得要命，真的是龟速，我没有耐心等待出结果；带缓冲的输入流的表现还不错，但相比内存映射文件就逊色多了。由此得出的结论就是：**内存映射文件，上G大文件轻松处理**。

### 05、最后

本篇文章主要介绍了 Java 的内存映射文件，MappedByteBuffer 是其灵魂，读取速度快如火箭。另外，所有这些示例和代码片段都可以[在 GitHub 上找到](https://github.com/qinggee/java)——这是一个 Maven 项目，所以它很容易导入和运行。
