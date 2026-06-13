module test;

/**
 * 动物基类
 */
class Animal
{
    /**
     * 动物名称
     */
    string name;
    
    /**
     * 发出声音
     */
    void speak();
}

/**
 * 可飞行接口
 */
interface IFlyable
{
    /**
     * 飞行动作
     */
    void fly();
}

/**
 * 狗类，继承自动物
 */
class Dog : Animal
{
    /**
     * 狗的品种
     */
    string breed;
    
    override void speak()
    {
        // 汪汪叫
    }
}

/**
 * 鸟类，继承自动物并实现飞行接口
 */
class Bird : Animal, IFlyable
{
    /**
     * 翅膀颜色
     */
    string wingColor;
    
    override void speak()
    {
        // 叽叽喳喳
    }
    
    void fly()
    {
        // 飞起来
    }
}

/**
 * 动物园类
 */
class Zoo
{
    /**
     * 动物园中的动物列表
     */
    Animal[] animals;
    
    /**
     * 添加动物
     */
    void addAnimal(Animal animal);
}

/**
 * 泛型容器模板
 */
template Container(T)
{
    T[] items;
    
    void add(T item)
    {
        items ~= item;
    }
}
