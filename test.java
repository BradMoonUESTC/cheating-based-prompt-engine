package com.example.test;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.function.Function;
import java.util.stream.Collectors;

@SuppressWarnings("all")
public class ComplexClass<T extends Comparable<T>> implements Cloneable {
    
    // 简单构造函数
    public ComplexClass() {
        System.out.println("Constructor");
    }

    // 带参数的构造函数
    protected ComplexClass(T initial, int... vars) throws IllegalArgumentException {
        this.value = initial;
    }

    // 泛型方法与复杂注解
    @SafeVarargs
    @SuppressWarnings({"unchecked", "rawtypes"})
    public static final <E extends Comparable<E>> List<E> complexGenericMethod(
            E[] elements,
            Function<E, String> mapper) throws IllegalArgumentException {
        return Arrays.stream(elements)
                .map(mapper)
                .map(s -> (E) s)
                .collect(Collectors.toList());
    }

    // 同步方法
    synchronized protected void synchronizedMethod() {
        try {
            wait(1000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }

    // 默认访问修饰符 + volatile
    volatile boolean checkStatus() {
        return status;
    }

    // 私有静态方法
    private static void privateStaticHelper() {
        System.out.println("Helper method");
    }

    // 带有默认值的接口方法
    interface TestInterface {
        default void defaultMethod(String param) {
            System.out.println(param);
        }
        
        static void staticInterfaceMethod() {
            System.out.println("Static interface method");
        }
    }

    // 抽象内部类
    abstract class AbstractInnerClass {
        abstract void abstractMethod();
        
        final void concreteMethod() {
            System.out.println("Concrete");
        }
    }

    // 异步方法
    @Deprecated
    public CompletableFuture<List<T>> asyncOperation(
            List<T> input,
            boolean parallel) {
        return CompletableFuture.supplyAsync(() -> {
            if (parallel) {
                return input.parallelStream()
                        .sorted()
                        .collect(Collectors.toList());
            }
            return new ArrayList<>(input);
        });
    }

    // native方法声明
    private native void nativeOperation();

    // 带有复杂泛型的方法
    public <K extends Comparable<K>, V extends List<? extends Number>> 
            Map<K, V> complexGenericOperation(K key, V value) throws Exception {
        return Collections.singletonMap(key, value);
    }

    // 函数式接口
    @FunctionalInterface
    interface ComplexFunction<X, Y, Z> {
        Z apply(X x, Y y);
    }

    // lambda表达式方法
    public void lambdaMethod() {
        ComplexFunction<String, Integer, Boolean> func = (str, num) -> {
            return str.length() > num;
        };
    }

    // 变长参数方法
    public static <T> void varArgsMethod(T... args) {
        for (T arg : args) {
            System.out.println(arg);
        }
    }

    // 内部类中的方法
    private class InnerClass {
        @Override
        protected Object clone() throws CloneNotSupportedException {
            return super.clone();
        }
        
        private <E> void innerGenericMethod(E element) {
            System.out.println(element);
        }
    }

    // 静态初始化块（虽然不是方法，但可以测试解析器的健壮性）
    static {
        System.out.println("Static initializer");
    }

    // 实例初始化块
    {
        System.out.println("Instance initializer");
    }

    // 带有多个注解的方法
    @Override
    @Deprecated
    @SuppressWarnings("unchecked")
    public synchronized String toString() {
        return super.toString();
    }

    // 返回数组的方法
    public int[][] create2DArray(int rows, int cols) {
        return new int[rows][cols];
    }

    // transient方法
    transient void transientMethod() {
        // 某些实现
    }

    // strictfp方法
    strictfp double strictFloatingPointMethod() {
        return 1.0;
    }

    // 带有throws声明的final方法
    protected final void throwingMethod() 
            throws IllegalArgumentException, NullPointerException {
        throw new IllegalArgumentException();
    }
}

// 额外的接口定义
interface AnotherTestInterface {
    void methodOne();
    
    // 接口中的默认方法
    default void methodTwo() {
        methodOne();
    }
    
    // 接口中的静态方法
    static void methodThree() {
        System.out.println("Static method in interface");
    }
}