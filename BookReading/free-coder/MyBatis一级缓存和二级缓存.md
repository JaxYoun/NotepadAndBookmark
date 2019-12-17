# MyBatis一级缓存和二级缓存

MyBatis自带一级和二级缓存

# 一级缓存

Mybatis的一级缓存是指Session缓存。一级缓存的作用域默认是一个SqlSession。Mybatis默认开启一级缓存。
也就是在同一个SqlSession中，执行相同的查询SQL，第一次会去数据库进行查询，并写到缓存中；第二次以后是直接去缓存中取。当执行l两次SQL查询之间发生了增删改的操作，MyBatis会把SqlSession的缓存清空。

![](./mybatisCacheLevel1.png)

一级缓存的范围有SESSION和STATEMENT两种，默认是SESSION，如果不想使用一级缓存，可以把一级缓存的范围指定为STATEMENT，这样每次执行完一个Mapper中的语句后都会将一级缓存清除。如果需要更改一级缓存的范围，可以在Mybatis的配置文件中，通过localCacheScope指定，但一般不建议修改。

<"localCacheScope" value="STATEMENT"/>

**注意：**当Mybatis整合Spring后，通过Spring注入Mapper实例的形式来查询时，如果**不在同一个事务**中，每个Mapper的每次查询操作都开启了一个全新的SqlSession实例，这个时候就不能命中一级缓存，但是在同一个事务中时由于多次查询共用的是同一个SqlSession，能命中缓存。如有实在需要缓存功能，就要启用二级缓存了。

# 二级缓存

Mybatis的二级缓存是指mapper映射文件级别的缓存。二级缓存的作用域是同一个namespace下的mapper映射文件内容，多个SqlSession都可共享。需要手动设置才能启动Mybatis的二级缓存功能。

![](./mybatisCacheLevel2.png)

二级缓存是默认启用的(**需要对每个Mapper进行配置**)，如想全局性的关闭，则可以通过Mybatis配置文件中的元素下的子元素来指定cacheEnabled为false。

<"cacheEnabled" value="false"/>

cacheEnabled默认是启用的，只有在该值为true的时候，底层使用的Executor才是支持二级缓存的CachingExecutor。具体可参考Mybatis的核心配置类org.apache.ibatis.session.Configuration的newExecutor方法实现。
可以通过源码看看

```java
public Executor newExecutor(Transaction transaction, ExecutorType executorType) {
    executorType = executorType == null ? this.defaultExecutorType : executorType;
    executorType = executorType == null ? ExecutorType.SIMPLE : executorType;
    Object executor;
    if (ExecutorType.BATCH == executorType) {
        executor = new BatchExecutor(this, transaction);
    } else if (ExecutorType.REUSE == executorType) {
        executor = new ReuseExecutor(this, transaction);
    } else {
        executor = new SimpleExecutor(this, transaction);
}
    if (this.cacheEnabled) {//设置为true才执行的
        executor = new CachingExecutor((Executor)executor);
    }
    Executor executor = (Executor)this.interceptorChain.pluginAll(executor);
    return executor;
}
```
要使用二级缓存除了上面一个配置外，我们还需要在我们目标DAO对应的Mapper.xml文件中定义需要使用的cache，定义格式如下：

<cache eviction="LRU" flushInterval="100000" readOnly="true" size="1024"/>

具体可以看org.apache.ibatis.executor.CachingExecutor类的以下实现
其中使用的cache就是我们在对应的Mapper.xml中定义的cache。
```java
public <E> List<E> query(MappedStatement ms, Object parameterObject, RowBounds rowBounds, ResultHandler resultHandler) throws SQLException {
    BoundSql boundSql = ms.getBoundSql(parameterObject);
    CacheKey key = this.createCacheKey(ms, parameterObject, rowBounds, boundSql);
    return this.query(ms, parameterObject, rowBounds, resultHandler, key, boundSql);
}

public <E> List<E> query(MappedStatement ms, Object parameterObject, RowBounds rowBounds, ResultHandler resultHandler, CacheKey key, BoundSql boundSql) throws SQLException {
    Cache cache = ms.getCache();
    if (cache != null) {//第一个条件 定义需要使用的cache 
        this.flushCacheIfRequired(ms);
        if (ms.isUseCache() && resultHandler == null) {//第二个条件 需要当前的查询语句是配置了使用cache的，即下面源码的useCache()是返回true的  默认是true
            this.ensureNoOutParams(ms, parameterObject, boundSql);
            List<E> list = (List)this.tcm.getObject(cache, key);
            if (list == null) {
                list = this.delegate.query(ms, parameterObject, rowBounds, resultHandler, key, boundSql);
                this.tcm.putObject(cache, key, list);
            }
            return list;
        }
    }
    return this.delegate.query(ms, parameterObject, rowBounds, resultHandler, key, boundSql);
}
```
从源码看，还需满足一个条件就是当前的查询语句的useCache属性是true，默认情况下所有select语句的useCache都是true。如果我们在启用了二级缓存后，需要排除某个查询语句的二级缓存时，就可以通过指定其useCache为false来达到排除效果。
如果我们不想该语句缓存，可使用useCache="false”，例如：

<select id="selectByPrimaryKey" resultMap="BaseResultMap" parameterType="java.lang.String" useCache="false">
        select
        <include refid="Base_Column_List"/>
        from tuser
        where id = #{id,jdbcType=VARCHAR}
</select>

## 两种声明使用cache的方式

上面说了要想使用二级缓存，需要在每个DAO对应的Mapper.xml文件中其中的查询语句需要使用cache来缓存数据的。有两种方式来完成声明：一种是通过cache元素定义，一种是通过cache-ref元素来定义。

**注意：**对于同一个Mapper来讲，只能使用一个Cache，当同时使用时，配置文件声明的cache优先级更高。Mapper使用的Cache是与我们的Mapper对应的namespace绑定的，**一个namespace最多只会有一个Cache**与其绑定。

### cache元素定义

使用cache元素来定义使用的Cache时，最简单的做法是直接在对应的Mapper.xml文件中指定一个空的元素(看前面的代码)，这个时候Mybatis会按照默认配置创建一个Cache对象，准备的说是PerpetualCache对象，更准确的说是LruCache对象（底层用了装饰器模式）。
具体的可看org.apache.ibatis.builder.xml.XMLMapperBuilder中的cacheElement()方法解析cache元素的逻辑。

```java
private void configurationElement(XNode context) {
	try {
		String namespace = context.getStringAttribute("namespace");
		if (namespace.equals("")) {
			throw new BuilderException("Mapper's namespace cannot be empty");
		} else {
			this.builderAssistant.setCurrentNamespace(namespace);
			this.cacheRefElement(context.evalNode("cache-ref"));
			//执行在后面
			this.cacheElement(context.evalNode("cache"));
			this.parameterMapElement(context.evalNodes("/mapper/parameterMap"));
			this.resultMapElements(context.evalNodes("/mapper/resultMap"));
			this.sqlElement(context.evalNodes("/mapper/sql"));
			this.buildStatementFromContext(context.evalNodes("select|insert|update|delete"));
		}
	} catch (Exception var3) {
		throw new BuilderException("Error parsing Mapper XML. Cause: " + var3, var3);
	}
}

private void cacheRefElement(XNode context) {
	if (context != null) {
		this.configuration.addCacheRef(this.builderAssistant.getCurrentNamespace(), context.getStringAttribute("namespace"));
		CacheRefResolver cacheRefResolver = new CacheRefResolver(this.builderAssistant, context.getStringAttribute("namespace"));
		try {
			cacheRefResolver.resolveCacheRef();
		} catch (IncompleteElementException var4) {
			this.configuration.addIncompleteCacheRef(cacheRefResolver);
		}
	}
}

private void cacheElement(XNode context) throws Exception {
	if (context != null) {
		String type = context.getStringAttribute("type", "PERPETUAL");
		Class<? extends Cache> typeClass = this.typeAliasRegistry.resolveAlias(type);
		String eviction = context.getStringAttribute("eviction", "LRU");
		Class<? extends Cache> evictionClass = this.typeAliasRegistry.resolveAlias(eviction);
		Long flushInterval = context.getLongAttribute("flushInterval");
		Integer size = context.getIntAttribute("size");
		boolean readWrite = !context.getBooleanAttribute("readOnly", false).booleanValue();
		Properties props = context.getChildrenAsProperties();
		//如果同时存在<cache>和<cache-ref>，这里的设置会覆盖前面的cache-ref的缓存
		this.builderAssistant.useNewCache(typeClass, evictionClass, flushInterval, size, readWrite, props);
	}
}
```
空cache元素定义会生成一个采用**最近最少使用**算法最多只能存储1024个元素的缓存，而且是可读写的缓存，即该缓存是全局共享的，任何一个线程在拿到缓存结果后对数据的修改都将影响其它线程获取的缓存结果，因为它们共享同一个对象。

<cache eviction="LRU" flushInterval="100000" readOnly="true" size="1024"/>

cache元素可指定如下属性，每种属性的指定都是针对都是针对底层Cache的一种装饰，采用的是装饰器的模式。

1. blocking：默认为false，当指定为true时将采用BlockingCache进行封装，blocking，阻塞的意思，使用BlockingCache会在查询缓存时锁住对应的Key，如果缓存命中了则会释放对应的锁，否则会在查询数据库以后再释放锁，这样可以阻止并发情况下多个线程同时查询数据，详情可参考BlockingCache的源码。

   简单理解，也就是设置true时，在进行增删改之后的并发查询，只会有一条去数据库查询，而不会并发

2. eviction：eviction，驱逐的意思。也就是元素驱逐算法，默认是LRU，对应的就是LruCache，其默认只保存1024个Key，超出时按照最近最少使用算法进行驱逐，详情请参考LruCache的源码。如果想使用自己的算法，则可以将该值指定为自己的驱逐算法实现类，只需要自己的类实现Mybatis的Cache接口即可。除了LRU以外，系统还提供了FIFO（先进先出，对应FifoCache）、SOFT（采用软引用存储Value，便于垃圾回收，对应SoftCache）和WEAK（采用弱引用存储Value，便于垃圾回收，对应WeakCache）这三种策略。
   这里，根据个人需求选择了，没什么要求的话，默认的LRU即可

3. flushInterval：清空缓存的时间间隔，单位是毫秒，默认是不会清空的。当指定了该值时会再用ScheduleCache包装一次，其会在每次对缓存进行操作时判断距离最近一次清空缓存的时间是否超过了flushInterval指定的时间，如果超出了，则清空当前的缓存，详情可参考ScheduleCache的实现。

4. readOnly：是否只读
   默认为false。当指定为false时，底层会用SerializedCache包装一次，其会在写缓存的时候将缓存对象进行序列化，然后在读缓存的时候进行反序列化，这样每次读到的都将是一个新的对象，即使你更改了读取到的结果，也不会影响原来缓存的对象，即非只读，你每次拿到这个缓存结果都可以进行修改，而不会影响原来的缓存结果；
   当指定为true时那就是每次获取的都是同一个引用，对其修改会影响后续的缓存数据获取，这种情况下是不建议对获取到的缓存结果进行更改，意为只读(不建议设置为true)。
   这是Mybatis二级缓存读写和只读的定义，可能与我们通常情况下的只读和读写意义有点不同。每次都进行序列化和反序列化无疑会影响性能，但是这样的缓存结果更安全，不会被随意更改，具体可根据实际情况进行选择。详情可参考SerializedCache的源码。

5. size：用来指定缓存中最多保存的Key的数量。其是针对LruCache而言的，LruCache默认只存储最多1024个Key，可通过该属性来改变默认值，当然，如果你通过eviction指定了自己的驱逐算法，同时自己的实现里面也有setSize方法，那么也可以通过cache的size属性给自定义的驱逐算法里面的size赋值。

6. type：type属性用来指定当前底层缓存实现类，默认是PerpetualCache，如果我们想使用自定义的Cache，则可以通过该属性来指定，对应的值是我们自定义的Cache的全路径名称。

### cache-ref元素定义

cache-ref元素可以用来指定其它Mapper.xml中定义的Cache，有的时候可能我们多个不同的Mapper需要共享同一个缓存的
是希望在MapperA中缓存的内容在MapperB中可以直接命中的，这个时候我们就可以考虑使用cache-ref，这种场景只需要保证它们的缓存的Key是一致的即可命中，二级缓存的Key是通过Executor接口的createCacheKey()方法生成的，其实现基本都是BaseExecutor，源码如下。

```java
public CacheKey createCacheKey(MappedStatement ms, Object parameterObject, RowBounds rowBounds, BoundSql boundSql) {
    if (this.closed) {
        throw new ExecutorException("Executor was closed.");
    } else {
        CacheKey cacheKey = new CacheKey();
        cacheKey.update(ms.getId());
        cacheKey.update(rowBounds.getOffset());
        cacheKey.update(rowBounds.getLimit());
        cacheKey.update(boundSql.getSql());
        List<ParameterMapping> parameterMappings = boundSql.getParameterMappings();
        TypeHandlerRegistry typeHandlerRegistry = ms.getConfiguration().getTypeHandlerRegistry();
        for(int i = 0; i < parameterMappings.size(); ++i) {
            ParameterMapping parameterMapping = (ParameterMapping)parameterMappings.get(i);
            if (parameterMapping.getMode() != ParameterMode.OUT) {
                String propertyName = parameterMapping.getProperty();
                Object value;
                if (boundSql.hasAdditionalParameter(propertyName)) {
                    value = boundSql.getAdditionalParameter(propertyName);
                } else if (parameterObject == null) {
                    value = null;
                } else if (typeHandlerRegistry.hasTypeHandler(parameterObject.getClass())) {
                    value = parameterObject;
                } else {
                    MetaObject metaObject = this.configuration.newMetaObject(parameterObject);
                    value = metaObject.getValue(propertyName);
                }
                cacheKey.update(value);
            }
        }
        return cacheKey;
    }
}
```

打个比方我想在MenuMapper.xml中的查询都使用在UserMapper.xml中定义的Cache，则可以通过cache-ref元素的namespace属性指定需要引用的Cache所在的namespace，即UserMapper.xml中的定义的namespace，假设在UserMapper.xml中定义的namespace是cn.chenhaoxiang.dao.UserMapper，则在MenuMapper.xml的cache-ref应该定义如下。这样这两个Mapper就共享同一个缓存了

<cache-ref namespace="cn.chenhaoxiang.dao.UserMapper"/>

## 测试二级缓存

![img](https://i.imgur.com/6TVsPr9.png)

查询测试

```java
@RunWith(SpringJUnit4ClassRunner.class)
//配置了@ContextConfiguration注解并使用该注解的locations属性指明spring和配置文件之后
@ContextConfiguration(locations = {"classpath:spring.xml","classpath:spring-mybatis.xml"})
public class MyBatisTestBySpringTestFramework {
    //注入userService
    @Autowired
    private UserService userService;
 
    @Test
    public void testGetUserId(){
        String userId = "4e07f3963337488e81716cfdd8a0fe04";
        User user = userService.getUserById(userId);
        System.out.println(user);

        //前面说到spring和MyBatis整合
        User user2 = userService.getUserById(userId);
        System.out.println("user2:"+user2);
    }
}
```

对二级缓存进行了以下测试，获取两个不同的SqlSession(前面有说，Spring和MyBatis集成，每次都是不同的SqlSession)执行两条相同的SQL，在未指定Cache时Mybatis将查询两次数据库，在指定了Cache时Mybatis只查询了一次数据库，第二次是从缓存中拿的。

Cache Hit Ratio 表示缓存命中率。
开启二级缓存后，每执行一次查询，系统都会计算一次二级缓存的命中率。
第一次查询也是先从缓存中查询，只不过缓存中一定是没有的。
所以会再从DB中查询。由于二级缓存中不存在该数据，所以命中率为0.但第二次查询是从二级缓存中读取的，所以这一次的命中率为1/2=0.5。
当然，若有第三次查询，则命中率为1/3=0.66
0.5这个值可以从上面开启cache的图看出来，0.0的值未截取到~漏掉了~

**注意：**增删改操作，无论是否进行提交sqlSession.commit()，均会清空一级、二级缓存，使查询再次从DB中select。
**说明：**二级缓存的清空，实质上是对所查找key对应的value置为null，而非将对应的entry对象删除。
从DB中进行select查询的条件是：缓存中**根本不存在这个key**或者缓存中**存在该key所对应的entry对象，但value为null**。

设置增删改操作不刷新二级缓存：若要使某个增、删或改操作不清空二级缓存，则需要在查询语句中中添加属性flushCache="false"，其默认值为true。

## 二级缓存的使用原则

1. 建议只在一个命名空间下使用二级缓存：
   由于二级缓存中的数据是基于namespace的，即不同namespace中的数据互不干扰。在多个namespace中若均存在对同一个表的操作，那么这多个namespace中的缓存数据可能就会出现不一致现象。
2. 在单表上使用二级缓存：
   如果一个表与其它表有关联关系，就非常有可能存在多个namespace对同一数据的操作。而不同namespace中的缓存数据互不干扰，所以就有可能出现多个namespace中的数据不一致现象。
3. 查询多于修改时使用二级缓存：
   在查询操作远远多于增删改操作的情况下可以使用二级缓存。因为任何增删改操作都将刷新二级缓存，对二级缓存的频繁刷新将降低系统性能。
